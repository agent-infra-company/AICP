import AppKit
import Combine
import Foundation
import SwiftUI

struct NotchDisplayInfo: Equatable {
    let hasNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let wingWidth: CGFloat
    let totalCollapsedWidth: CGFloat

    static let noNotch = NotchDisplayInfo(
        hasNotch: false,
        notchWidth: 0,
        notchHeight: 38,
        wingWidth: 0,
        totalCollapsedWidth: 340
    )
}

struct NotchToast: Equatable {
    let id: UUID
    let sourceKind: TaskSourceKind
    let title: String
    let status: TaskStatus
    let displayTask: DisplayTask

    static func == (lhs: NotchToast, rhs: NotchToast) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class CompanionCore: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case compose = "Compose"
        case running = "Running"
        case needsInput = "Needs Input"
        case history = "History"

        var id: String { rawValue }
    }

    @Published var isExpanded: Bool = false
    @Published var showingFullTaskList: Bool = false
    @Published var selectedTab: Tab = .compose

    @Published var profiles: [ProfileConfig] = []
    @Published var commandTemplateSets: [CommandTemplateSet] = []
    @Published var routesByProfile: [UUID: [RouteInfo]] = [:]
    @Published var tasks: [TaskRecord] = []
    @Published var settings: AppSettings = .default

    @Published var composePrompt: String = ""
    @Published var runtimeStatusByProfile: [UUID: RuntimeStatus] = [:]
    @Published var connectionStateByProfile: [UUID: String] = [:]
    @Published var pendingRuntimeOperation: PendingRuntimeOperation?
    @Published var lastErrorBanner: String?
    @Published var notchDisplayInfo: NotchDisplayInfo = .noNotch
    @Published var isSubmitting: Bool = false
    @Published var externalSnapshots: [TaskSourceKind: [ExternalTaskSnapshot]] = [:]
    @Published var activeToast: NotchToast?

    private let stateMachine = TaskStateMachine()
    private let gatewayClient: GatewayClient
    private let runtimeManager: RuntimeManager
    private let persistenceStore: PersistenceStore
    private let notificationService: NotificationService
    private let telemetryManager: TelemetryManaging
    private let loginItemManager: LoginItemManaging
    private let retentionManager: RetentionManaging
    private let taskSourceAggregator: TaskSourceAggregator

    private var eventTasks: [UUID: Task<Void, Never>] = [:]
    private var aggregatorTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    init(
        gatewayClient: GatewayClient,
        runtimeManager: RuntimeManager,
        persistenceStore: PersistenceStore,
        notificationService: NotificationService,
        telemetryManager: TelemetryManaging,
        loginItemManager: LoginItemManaging,
        retentionManager: RetentionManaging,
        taskSourceAggregator: TaskSourceAggregator
    ) {
        self.gatewayClient = gatewayClient
        self.runtimeManager = runtimeManager
        self.persistenceStore = persistenceStore
        self.notificationService = notificationService
        self.telemetryManager = telemetryManager
        self.loginItemManager = loginItemManager
        self.retentionManager = retentionManager
        self.taskSourceAggregator = taskSourceAggregator
    }

    deinit {
        for task in eventTasks.values {
            task.cancel()
        }
        aggregatorTask?.cancel()
    }

    func bootstrap() async {
        do {
            let state = try await persistenceStore.loadState()
            apply(state: state)
        } catch {
            lastErrorBanner = error.localizedDescription
        }

        do {
            try await notificationService.prepare()
        } catch {
            telemetryManager.record(.error("Notification authorization failed: \(error.localizedDescription)"))
        }

        telemetryManager.setOptIn(settings.telemetryOptIn)
        await runtimeManager.updateConfiguration(profiles: profiles, templateSets: commandTemplateSets)
        updateLaunchAtLoginSetting()
        retentionManager.schedule(retentionDays: settings.retentionDays) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.enforceRetentionPolicy()
            }
        }

        if let profile = selectedProfile {
            await refreshRoutes(profile)
        }

        await startExternalTaskMonitoring()
    }

    var allDisplayTasks: [DisplayTask] {
        let openClawTasks = tasks
            .filter { !$0.status.isTerminal }
            .map { DisplayTask(from: $0, profiles: profiles) }
        let externalTasks = externalSnapshots.values
            .flatMap { $0 }
            .map { DisplayTask(from: $0) }
        return (openClawTasks + externalTasks)
            .sorted(by: displayTaskOrdering)
    }

    /// Tasks shown in the notch: all running/active first, then fill to 5 with recent terminal tasks.
    var notchDisplayTasks: [DisplayTask] {
        let maxVisible = 5
        let all = allDisplayTasksIncludingTerminal
        let active = all.filter { !$0.status.isTerminal }
        if active.count >= maxVisible {
            return active
        }
        let recent = all.filter { $0.status.isTerminal }.prefix(maxVisible - active.count)
        return active + recent
    }

    /// All tasks including terminal, for the full task list view.
    var allDisplayTasksIncludingTerminal: [DisplayTask] {
        let openClawTasks = tasks
            .map { DisplayTask(from: $0, profiles: profiles) }
        let externalTasks = externalSnapshots.values
            .flatMap { $0 }
            .map { DisplayTask(from: $0) }
        return (openClawTasks + externalTasks)
            .sorted(by: displayTaskOrdering)
    }

    /// Sort by status priority first, then by most recently updated within each group.
    private func displayTaskOrdering(_ a: DisplayTask, _ b: DisplayTask) -> Bool {
        if a.sortPriority != b.sortPriority {
            return a.sortPriority < b.sortPriority
        }
        return a.updatedAt > b.updatedAt
    }

    var allRunningCount: Int {
        allDisplayTasks.filter { [.queued, .running].contains($0.status) }.count
    }

    var allNeedsInputCount: Int {
        allDisplayTasks.filter { $0.status == .needsInput }.count
    }

    func openTask(_ displayTask: DisplayTask) {
        if displayTask.sourceKind == .openClaw {
            let rawId = String(displayTask.id.dropFirst("openclaw-".count))
            focusTask(rawId)
            return
        }

        // Collapse the notch so the target app is visible and focused
        setExpanded(false)

        if activateApp(for: displayTask) {
            return
        }

        if let url = displayTask.deepLinkURL {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private func activateApp(for displayTask: DisplayTask) -> Bool {
        for bundleId in displayTask.sourceKind.activationBundleIdentifiers {
            if activateApp(bundleId: bundleId) {
                return true
            }
        }

        for appPath in displayTask.sourceKind.activationApplicationPaths {
            guard FileManager.default.fileExists(atPath: appPath) else {
                continue
            }
            openApplication(at: URL(fileURLWithPath: appPath))
            return true
        }

        return false
    }

    @discardableResult
    private func activateApp(bundleId: String) -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { !$0.isTerminated }

        if let app = runningApps.first {
            app.unhide()
            return app.activate(options: [.activateAllWindows])
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            openApplication(at: url)
            return true
        }

        return false
    }

    private func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    var selectedProfile: ProfileConfig? {
        profiles.first(where: { $0.id == settings.selectedProfileId })
    }

    var selectedRouteId: String {
        guard let profile = selectedProfile else {
            return "default"
        }
        return settings.selectedRouteByProfile[profile.id] ?? "default"
    }

    var runningTasks: [TaskRecord] {
        tasks.filter { [.queued, .running].contains($0.status) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var needsInputTasks: [TaskRecord] {
        tasks.filter { $0.status == .needsInput }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var historyTasks: [TaskRecord] {
        tasks.filter { [.completed, .failed, .canceled, .needsAttention].contains($0.status) }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    func setExpanded(_ expanded: Bool) {
        if !expanded {
            guard !isSubmitting else { return }
            guard pendingRuntimeOperation == nil else { return }
            showingFullTaskList = false
        }
        isExpanded = expanded
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    func selectProfile(_ profileId: UUID) {
        settings.selectedProfileId = profileId
        if settings.selectedRouteByProfile[profileId] == nil {
            settings.selectedRouteByProfile[profileId] = routesByProfile[profileId]?.first?.id ?? "default"
        }
        persistAsync()

        if let profile = selectedProfile {
            Task {
                await refreshRoutes(profile)
            }
        }
    }

    func selectRoute(_ routeId: String) {
        guard let profileId = settings.selectedProfileId else {
            return
        }
        settings.selectedRouteByProfile[profileId] = routeId
        persistAsync()
    }

    func submitPrompt() async {
        let prompt = composePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            lastErrorBanner = "Prompt cannot be empty."
            return
        }

        guard let profile = selectedProfile else {
            lastErrorBanner = "Select a profile before sending a task."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let routeId = selectedRouteId
        var task = TaskRecord.draft(profileId: profile.id, routeId: routeId, prompt: prompt)

        do {
            task = try stateMachine.transition(task, to: .queued)
            upsert(task)
            composePrompt = ""
            selectedTab = .running

            try await ensureRuntimeHealthy(for: profile)
            try await ensureConnected(profile)

            let draft = TaskDraft(
                profileId: profile.id,
                routeId: routeId,
                title: task.title,
                prompt: task.prompt,
                clientTaskId: task.taskId
            )

            let sentInfo = try await gatewayClient.sendTask(draft, profile: profile)
            task.taskId = sentInfo.taskId
            task.sessionId = sentInfo.sessionId
            task.runId = sentInfo.runId
            task = try stateMachine.transition(task, to: sentInfo.status)
            upsert(task)

            telemetryManager.record(.taskSubmitted(taskId: task.taskId, profileId: profile.id, routeId: routeId))
        } catch {
            await handleTaskFailure(taskId: task.taskId, reason: error.localizedDescription)
        }
    }

    func answerFollowUp(taskId: String, answer: String) async {
        guard let task = tasks.first(where: { $0.taskId == taskId }) else {
            return
        }

        guard let profile = profiles.first(where: { $0.id == task.profileId }) else {
            lastErrorBanner = "Profile unavailable for follow-up response."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await gatewayClient.answerFollowUp(task: task, answer: answer, profile: profile)
            var updated = try stateMachine.transition(task, to: .running)
            updated.latestProgress = "Follow-up answer submitted"
            upsert(updated)
            selectedTab = .running
        } catch {
            lastErrorBanner = "Failed to answer follow-up: \(error.localizedDescription)"
        }
    }

    func requestRuntimeAction(_ action: RuntimeAction) async {
        guard let profile = selectedProfile else {
            return
        }

        switch confirmationRequirement(for: action, profileName: profile.name) {
        case .notRequired:
            await executeRuntimeAction(action, for: profile.id)
        case let .required(title, message):
            pendingRuntimeOperation = PendingRuntimeOperation(
                profileId: profile.id,
                action: action,
                title: title,
                message: message
            )
        }
    }

    func confirmPendingRuntimeAction() async {
        guard let pendingRuntimeOperation else {
            return
        }
        self.pendingRuntimeOperation = nil
        await executeRuntimeAction(pendingRuntimeOperation.action, for: pendingRuntimeOperation.profileId)
    }

    func clearPendingRuntimeAction() {
        pendingRuntimeOperation = nil
    }

    func completeOnboarding() {
        updateSetting { $0.hasCompletedOnboarding = true }
    }

    func requestNotificationAuthorization() async -> Bool {
        do {
            return try await notificationService.requestAuthorization()
        } catch {
            telemetryManager.record(.error("Notification authorization failed: \(error.localizedDescription)"))
            lastErrorBanner = "Notification authorization failed: \(error.localizedDescription)"
            return false
        }
    }

    func updateSetting(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        telemetryManager.setOptIn(settings.telemetryOptIn)
        updateLaunchAtLoginSetting()
        persistAsync()
    }

    func upsertProfile(_ profile: ProfileConfig) {
        if let existingIndex = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[existingIndex] = profile
        } else {
            profiles.append(profile)
        }

        if settings.selectedProfileId == nil {
            settings.selectedProfileId = profile.id
        }

        syncRuntimeConfigurationAsync()
        persistAsync()
    }

    func upsertCommandTemplateSet(_ templateSet: CommandTemplateSet) {
        if let index = commandTemplateSets.firstIndex(where: { $0.id == templateSet.id }) {
            commandTemplateSets[index] = templateSet
        } else {
            commandTemplateSets.append(templateSet)
        }
        syncRuntimeConfigurationAsync()
        persistAsync()
    }

    func refreshRoutes(_ profile: ProfileConfig) async {
        do {
            let routes = try await gatewayClient.discoverRoutes(profile: profile)
            routesByProfile[profile.id] = routes
            if settings.selectedRouteByProfile[profile.id] == nil {
                settings.selectedRouteByProfile[profile.id] = routes.first?.id ?? "default"
            }
            persistAsync()
        } catch {
            telemetryManager.record(.error("Route discovery failed for \(profile.name): \(error.localizedDescription)"))
        }
    }

    func shouldShowFullscreen() -> Bool {
        settings.showInFullscreen
    }

    func shouldHideFromScreenRecording() -> Bool {
        settings.hideInScreenRecording
    }

    func focusTask(_ taskId: String) {
        guard let task = tasks.first(where: { $0.taskId == taskId }) else {
            return
        }
        isExpanded = true
        switch task.status {
        case .needsInput:
            selectedTab = .needsInput
        case .queued, .running:
            selectedTab = .running
        default:
            selectedTab = .history
        }
    }

    private func ensureRuntimeHealthy(for profile: ProfileConfig) async throws {
        let status = try await runtimeManager.status(profileId: profile.id)
        runtimeStatusByProfile[profile.id] = status
        if status.isHealthy {
            return
        }

        _ = try await runtimeManager.start(profileId: profile.id)
        let postStart = try await runtimeManager.status(profileId: profile.id)
        runtimeStatusByProfile[profile.id] = postStart

        guard postStart.isHealthy else {
            throw RuntimeManagerError.unhealthy(postStart.detail)
        }
    }

    private func ensureConnected(_ profile: ProfileConfig) async throws {
        if connectionStateByProfile[profile.id] == "connected" {
            return
        }

        try await gatewayClient.connect(profile: profile)
        connectionStateByProfile[profile.id] = "connected"
        await startEventConsumptionIfNeeded(profileId: profile.id)
    }

    private func startEventConsumptionIfNeeded(profileId: UUID) async {
        guard eventTasks[profileId] == nil else {
            return
        }

        let stream = await gatewayClient.subscribeEvents(profileId: profileId)
        eventTasks[profileId] = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.process(event: event)
            }
            await MainActor.run {
                self.connectionStateByProfile[profileId] = "disconnected"
                self.eventTasks[profileId] = nil
            }
        }
    }

    private func process(event: GatewayEventEnvelope) async {
        guard let taskId = event.taskId,
              var task = tasks.first(where: { $0.taskId == taskId }) else {
            return
        }

        do {
            switch event.eventType {
            case "progress", "run_progress":
                if task.status == .queued {
                    task = try stateMachine.transition(task, to: .running)
                }
                task.latestProgress = event.payload["message"] ?? "Working"
            case "needs_input", "question":
                task = try stateMachine.transition(task, to: .needsInput)
                task.needsInputPrompt = event.payload["question"] ?? event.payload["prompt"] ?? "Agent needs input"
                await notificationService.sendTaskNeedsInput(task)
            case "completed", "done":
                task = try stateMachine.transition(task, to: .completed)
                await notificationService.sendTaskCompleted(task)
            case "failed", "error":
                let reason = event.payload["error"] ?? "Run failed"
                await handleTaskFailure(taskId: task.taskId, reason: reason)
                return
            case "canceled":
                task = try stateMachine.transition(task, to: .canceled)
            default:
                task.latestProgress = event.payload["message"] ?? "Event: \(event.eventType)"
            }

            if let runId = event.runId {
                task.runId = runId
            }
            if let sessionId = event.sessionId {
                task.sessionId = sessionId
            }
            upsert(task)
        } catch {
            telemetryManager.record(.error("Event processing failed for \(task.taskId): \(error.localizedDescription)"))
        }
    }

    private func handleTaskFailure(taskId: String, reason: String) async {
        guard var task = tasks.first(where: { $0.taskId == taskId }) else {
            return
        }

        do {
            task = try stateMachine.transition(task, to: .failed)
            task.lastError = reason

            if task.retryCount < 1 {
                task.retryCount += 1
                upsert(task)
                telemetryManager.record(.taskAutoRetry(taskId: task.taskId, count: task.retryCount))

                guard let profile = profiles.first(where: { $0.id == task.profileId }) else {
                    throw RuntimeManagerError.profileMissing
                }

                try await ensureConnected(profile)
                let retryDraft = TaskDraft(
                    profileId: task.profileId,
                    routeId: task.routeId,
                    title: task.title,
                    prompt: task.prompt,
                    clientTaskId: task.taskId
                )
                _ = try await gatewayClient.sendTask(retryDraft, profile: profile)
                task = try stateMachine.transition(task, to: .queued)
                task.latestProgress = "Retrying after transient failure"
                upsert(task)
                return
            }

            task = try stateMachine.transition(task, to: .needsAttention)
            upsert(task)
            await notificationService.sendTaskFailed(task)
        } catch {
            lastErrorBanner = "Task failure handling error: \(error.localizedDescription)"
        }
    }

    private func executeRuntimeAction(_ action: RuntimeAction, for profileId: UUID) async {
        do {
            let status: RuntimeStatus
            switch action {
            case .start:
                status = try await runtimeManager.start(profileId: profileId)
            case .stop:
                status = try await runtimeManager.stop(profileId: profileId)
            case .restart:
                status = try await runtimeManager.restart(profileId: profileId)
            case .status:
                status = try await runtimeManager.status(profileId: profileId)
            }
            runtimeStatusByProfile[profileId] = status
            telemetryManager.record(.runtimeAction(action.rawValue, profileId: profileId, healthy: status.isHealthy))
        } catch {
            lastErrorBanner = "Runtime \(action.rawValue) failed: \(error.localizedDescription)"
        }
    }

    private func confirmationRequirement(for action: RuntimeAction, profileName: String) -> RuntimeRequestConfirmation {
        switch action {
        case .stop:
            return .required(
                title: "Stop runtime?",
                message: "Stop OpenClaw for \(profileName)? Active runs may interrupt."
            )
        case .restart:
            return .required(
                title: "Restart runtime?",
                message: "Restart OpenClaw for \(profileName)? Active runs may reconnect."
            )
        case .start, .status:
            return .notRequired
        }
    }

    private func upsert(_ task: TaskRecord) {
        if let index = tasks.firstIndex(where: { $0.taskId == task.taskId }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        persistAsync()
    }

    private func apply(state: PersistedState) {
        profiles = state.profiles
        commandTemplateSets = state.commandTemplateSets
        tasks = state.tasks
        routesByProfile = state.routeAliasesByProfile
        settings = state.settings

        if settings.selectedProfileId == nil {
            settings.selectedProfileId = profiles.first?.id
        }

        telemetryManager.setOptIn(settings.telemetryOptIn)
    }

    private func persistAsync() {
        let state = PersistedState(
            profiles: profiles,
            commandTemplateSets: commandTemplateSets,
            tasks: tasks,
            routeAliasesByProfile: routesByProfile,
            settings: settings,
            updatedAt: Date()
        )

        Task {
            do {
                try await persistenceStore.saveState(state)
            } catch {
                await MainActor.run {
                    self.lastErrorBanner = "Failed to persist state: \(error.localizedDescription)"
                }
            }
        }
    }

    private func enforceRetentionPolicy() async {
        let threshold = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date()) ?? .distantPast
        tasks.removeAll(where: { $0.updatedAt < threshold })
        persistAsync()
    }

    private func updateLaunchAtLoginSetting() {
        guard AppRuntimeEnvironment.current.supportsLoginItemRegistration else {
            return
        }

        do {
            try loginItemManager.setEnabled(settings.launchAtLogin)
        } catch {
            telemetryManager.record(.error("Launch at login update failed: \(error.localizedDescription)"))
        }
    }

    private func syncRuntimeConfigurationAsync() {
        let profiles = self.profiles
        let commandTemplateSets = self.commandTemplateSets
        Task {
            await runtimeManager.updateConfiguration(profiles: profiles, templateSets: commandTemplateSets)
        }
    }

    func showToast(for snapshot: ExternalTaskSnapshot) {
        let display = DisplayTask(from: snapshot)
        let toast = NotchToast(
            id: UUID(),
            sourceKind: snapshot.sourceKind,
            title: snapshot.title,
            status: snapshot.status,
            displayTask: display
        )
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activeToast = toast
        }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    if self.activeToast?.id == toast.id {
                        self.activeToast = nil
                    }
                }
            }
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            activeToast = nil
        }
    }

    func handleToastTap() {
        guard let toast = activeToast else { return }
        openTask(toast.displayTask)
        dismissToast()
    }

    private func startExternalTaskMonitoring() async {
        await taskSourceAggregator.startAll()

        aggregatorTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.taskSourceAggregator.snapshotStream
            for await newSnapshots in stream {
                await MainActor.run {
                    self.processExternalSnapshots(newSnapshots)
                }
            }
        }
    }

    private func processExternalSnapshots(_ new: [TaskSourceKind: [ExternalTaskSnapshot]]) {
        let oldFlat = externalSnapshots.values.flatMap { $0 }
        let newFlat = new.values.flatMap { $0 }

        for snapshot in newFlat {
            let old = oldFlat.first(where: { $0.id == snapshot.id && $0.sourceKind == snapshot.sourceKind })

            if let old {
                let statusChanged = old.status != snapshot.status
                // Detect completed turns: status stayed .needsInput but updatedAt moved forward,
                // meaning a full turn (user → assistant) happened between polls.
                let turnCompleted = snapshot.status == .needsInput
                    && old.status == .needsInput
                    && snapshot.updatedAt.timeIntervalSince(old.updatedAt) > 1
                guard statusChanged || turnCompleted else { continue }
            }
            // New tasks (old == nil) always get a notification

            switch snapshot.status {
            case .running, .queued:
                Task { await notificationService.sendExternalTaskStarted(snapshot) }
            case .needsInput:
                Task { await notificationService.sendExternalTaskNeedsInput(snapshot) }
            case .completed:
                Task { await notificationService.sendExternalTaskCompleted(snapshot) }
            case .failed, .needsAttention:
                Task { await notificationService.sendExternalTaskFailed(snapshot) }
            default:
                break
            }
            showToast(for: snapshot)
        }

        // Detect disappeared tasks — previously running tasks that are no longer present
        for old in oldFlat {
            guard old.status == .running else { continue }
            let stillPresent = newFlat.contains { $0.id == old.id && $0.sourceKind == old.sourceKind }
            guard !stillPresent else { continue }

            let completed = ExternalTaskSnapshot(
                id: old.id,
                sourceKind: old.sourceKind,
                title: old.title,
                workspace: old.workspace,
                status: .completed,
                progress: nil,
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: Date(),
                deepLinkURL: old.deepLinkURL,
                metadata: old.metadata
            )
            Task { await notificationService.sendExternalTaskCompleted(completed) }
            showToast(for: completed)
        }

        externalSnapshots = new
    }
}
