import AppKit
import Combine
import Foundation
import SwiftUI
import os.log

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

struct ExternalSnapshotActivityDetector {
    static func shouldAnnounce(old: ExternalTaskSnapshot?, new: ExternalTaskSnapshot) -> Bool {
        guard let old else { return true }
        guard old.id == new.id, old.sourceKind == new.sourceKind else { return true }

        if old.status != new.status {
            return true
        }

        let updatedRecently = new.updatedAt.timeIntervalSince(old.updatedAt) > 1
        guard updatedRecently else { return false }

        if new.status == .needsInput && old.status == .needsInput {
            return true
        }

        return new.sourceKind == .codex
            && old.sourceKind == .codex
            && new.status == .running
            && old.status == .running
            && new.metadata["source"] == "cli"
            && old.metadata["source"] == "cli"
            && codexCLITurnChanged(old: old, new: new)
    }

    private static func codexCLITurnChanged(old: ExternalTaskSnapshot, new: ExternalTaskSnapshot) -> Bool {
        let oldTurnId = old.metadata["turnId"]
        let newTurnId = new.metadata["turnId"]

        if let oldTurnId, let newTurnId {
            return oldTurnId != newTurnId
        }

        return true
    }
}

@MainActor
final class CompanionCore: ObservableObject {
    private static let log = CompanionDiagnostics.logger(category: "CompanionCore")

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

    @Published var selectedCLI: TaskSourceKind = .claudeCode
    @Published var availableCLIs: [TaskSourceKind] = []
    @Published var archivedTaskIds: Set<String> = []

    private let stateMachine = TaskStateMachine()
    private let gatewayClient: GatewayClient
    private let runtimeManager: RuntimeManager
    private let persistenceStore: PersistenceStore
    private let notificationService: NotificationService
    private let telemetryManager: TelemetryManaging
    private let loginItemManager: LoginItemManaging
    private let retentionManager: RetentionManaging
    private let taskSourceAggregator: TaskSourceAggregator
    private let cliSessionLauncher: CLISessionLauncher
    private let secretStore: SecretStoring?

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
        taskSourceAggregator: TaskSourceAggregator,
        cliSessionLauncher: CLISessionLauncher = CLISessionLauncher(),
        secretStore: SecretStoring? = nil
    ) {
        self.gatewayClient = gatewayClient
        self.runtimeManager = runtimeManager
        self.persistenceStore = persistenceStore
        self.notificationService = notificationService
        self.telemetryManager = telemetryManager
        self.loginItemManager = loginItemManager
        self.retentionManager = retentionManager
        self.taskSourceAggregator = taskSourceAggregator
        self.cliSessionLauncher = cliSessionLauncher
        self.secretStore = secretStore
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

        await detectAvailableCLIs()

        await startExternalTaskMonitoring()
    }

    var allDisplayTasks: [DisplayTask] {
        let openClawTasks = tasks
            .filter { !$0.status.isTerminal }
            .map { DisplayTask(from: $0, profiles: profiles) }
        let externalTasks = externalSnapshots
            .filter { $0.key != .webAIChat }
            .values.flatMap { $0 }
            .map { DisplayTask(from: $0) }
        return (openClawTasks + externalTasks)
            .filter { !archivedTaskIds.contains($0.id) }
            .sorted(by: Self.displayTaskOrdering)
    }

    /// Tasks shown in the notch, sorted by most recently updated first, capped at 10.
    var notchDisplayTasks: [DisplayTask] {
        Array(allDisplayTasksIncludingTerminal.prefix(10))
    }

    /// All tasks including terminal, for the full task list view.
    var allDisplayTasksIncludingTerminal: [DisplayTask] {
        let openClawTasks = tasks
            .map { DisplayTask(from: $0, profiles: profiles) }
        let externalTasks = externalSnapshots
            .filter { $0.key != .webAIChat }
            .values.flatMap { $0 }
            .map { DisplayTask(from: $0) }
        return (openClawTasks + externalTasks)
            .filter { !archivedTaskIds.contains($0.id) }
            .sorted(by: Self.displayTaskOrdering)
    }

    /// Sort by most recently updated first.
    private nonisolated static func displayTaskOrdering(_ a: DisplayTask, _ b: DisplayTask) -> Bool {
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
        Self.log.info(
            "Opening task id=\(displayTask.id, privacy: .public) source=\(displayTask.sourceKind.rawValue, privacy: .public) title=\(displayTask.title, privacy: .public)"
        )

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
            Self.log.info(
                "Falling back to deep link source=\(displayTask.sourceKind.rawValue, privacy: .public) url=\(url.absoluteString, privacy: .public)"
            )
            NSWorkspace.shared.open(url)
        } else {
            Self.log.warning(
                "No activation target or deep link available for source=\(displayTask.sourceKind.rawValue, privacy: .public)"
            )
        }
    }

    func archiveTask(_ displayTask: DisplayTask) {
        Self.log.info(
            "Archiving task id=\(displayTask.id, privacy: .public) source=\(displayTask.sourceKind.rawValue, privacy: .public)"
        )
        archivedTaskIds.insert(displayTask.id)
        persistAsync()
    }

    @discardableResult
    private func activateApp(for displayTask: DisplayTask) -> Bool {
        let bundleIdentifiers = displayTask.activationBundleIdentifiers
        let applicationPaths = displayTask.activationApplicationPaths

        Self.log.debug(
            "Attempting activation source=\(displayTask.sourceKind.rawValue, privacy: .public) bundleIds=\(CompanionDiagnostics.joined(bundleIdentifiers), privacy: .public) paths=\(CompanionDiagnostics.joined(applicationPaths), privacy: .public)"
        )

        for bundleId in bundleIdentifiers {
            if activateApp(bundleId: bundleId) {
                return true
            }
        }

        for appPath in applicationPaths {
            guard FileManager.default.fileExists(atPath: appPath) else {
                Self.log.debug("Activation path missing path=\(appPath, privacy: .public)")
                continue
            }
            Self.log.info("Opening app by path path=\(appPath, privacy: .public)")
            openApplication(at: URL(fileURLWithPath: appPath))
            return true
        }

        Self.log.warning("Activation failed for source=\(displayTask.sourceKind.rawValue, privacy: .public)")
        return false
    }

    @discardableResult
    private func activateApp(bundleId: String) -> Bool {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { !$0.isTerminated }

        if let app = runningApps.first {
            app.unhide()
            let activated = app.activate(options: [.activateAllWindows])
            Self.log.info(
                "Activated running app bundleId=\(bundleId, privacy: .public) success=\(activated)"
            )
            return activated
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Self.log.info(
                "Launching app from bundle identifier bundleId=\(bundleId, privacy: .public) url=\(url.path, privacy: .public)"
            )
            openApplication(at: url)
            return true
        }

        Self.log.warning("No app resolved for bundleId=\(bundleId, privacy: .public)")
        return false
    }

    private func openApplication(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        Self.log.debug("openApplication path=\(url.path, privacy: .public)")
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

        switch selectedCLI {
        case .claudeCode, .codex:
            await submitCLISession(prompt: prompt, cli: selectedCLI)
        case .openClaw:
            await submitOpenClawTask(prompt: prompt)
        default:
            lastErrorBanner = "\(selectedCLI.displayName) is not supported for new sessions."
        }
    }

    private func submitOpenClawTask(prompt: String) async {
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
            let previousTaskId = task.taskId
            task = try applyGatewaySubmission(sentInfo, to: task)
            upsert(task, replacingTaskId: previousTaskId == task.taskId ? nil : previousTaskId)
            showToast(for: task)
            setExpanded(false)

            telemetryManager.record(.taskSubmitted(taskId: task.taskId, profileId: profile.id, routeId: routeId))
        } catch {
            await handleTaskFailure(taskId: task.taskId, reason: error.localizedDescription)
        }
    }

    private func submitCLISession(prompt: String, cli: TaskSourceKind) async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        await launchCLISession(prompt: prompt, cli: cli, cwd: home)
    }

    private func launchCLISession(prompt: String, cli: TaskSourceKind, cwd: String) async {
        guard FileManager.default.fileExists(atPath: cwd) else {
            lastErrorBanner = "Directory not found: \(cwd)"
            return
        }

        isSubmitting = true

        do {
            try await cliSessionLauncher.launch(cli: cli, prompt: prompt, cwd: cwd)
            composePrompt = ""
            isSubmitting = false

            // Collapse the notch so the terminal is visible
            setExpanded(false)

            // The existing task source polling (ClaudeCodeTaskSource / CodexTaskSource)
            // will detect the new session within a few seconds and show it in the task list.
        } catch {
            isSubmitting = false
            lastErrorBanner = error.localizedDescription
        }
    }

    func selectCLI(_ cli: TaskSourceKind) {
        selectedCLI = cli
        settings.selectedCLI = cli.rawValue
        persistAsync()
    }

    private func detectAvailableCLIs() async {
        var available: [TaskSourceKind] = []

        if await cliSessionLauncher.isAvailable(.claudeCode) {
            available.append(.claudeCode)
        }
        if await cliSessionLauncher.isAvailable(.codex) {
            available.append(.codex)
        }
        if !profiles.isEmpty {
            available.append(.openClaw)
        }

        availableCLIs = available

        // Restore persisted selection or default to first available
        if let savedCLI = settings.selectedCLI,
           let kind = TaskSourceKind(rawValue: savedCLI),
           available.contains(kind) {
            selectedCLI = kind
        } else if let first = available.first {
            selectedCLI = first
        }

        Self.log.info(
            "Detected available CLIs: \(CompanionDiagnostics.joined(available.map(\.displayName)), privacy: .public) selected=\(self.selectedCLI.displayName, privacy: .public)"
        )
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

    func saveCredential(_ value: String, forRef ref: String) {
        try? secretStore?.setSecret(value, for: ref)
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
        // Remote gateways can be managed externally; don't block task submission
        // on runtime SSH controls when no SSH target is configured.
        if profile.kind == .remote,
           profile.sshRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            runtimeStatusByProfile[profile.id] = RuntimeStatus(
                isHealthy: true,
                detail: "Runtime managed externally",
                checkedAt: Date()
            )
            return
        }

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
        guard var task = taskMatching(event: event) else {
            return
        }

        do {
            let previousStatus = task.status
            let previousTaskId = task.taskId

            switch eventStatus(for: event) {
            case let .progress(message):
                task = try transitionIfNeeded(task, to: .running)
                task.latestProgress = message ?? event.payload["summary"] ?? "Working"
            case let .needsInput(prompt):
                task = try transitionIfNeeded(task, to: .needsInput)
                task.needsInputPrompt = prompt ?? "Agent needs input"
                await notificationService.sendTaskNeedsInput(task)
            case let .completed(message):
                task = try transitionIfNeeded(task, to: .completed)
                if let message, !message.isEmpty {
                    task.latestProgress = message
                }
                await notificationService.sendTaskCompleted(task)
            case let .failed(reason):
                await handleTaskFailure(taskId: task.taskId, reason: reason)
                return
            case .canceled:
                task = try transitionIfNeeded(task, to: .canceled)
            case let .ignored(message):
                if let message, !message.isEmpty {
                    task.latestProgress = message
                }
            }

            if let canonicalTaskId = event.taskId, !canonicalTaskId.isEmpty {
                task.taskId = canonicalTaskId
            } else if let runId = event.runId, !runId.isEmpty {
                task.taskId = runId
            }
            if let runId = event.runId {
                task.runId = runId
            }
            if let sessionId = event.sessionId {
                task.sessionId = sessionId
            }
            upsert(task, replacingTaskId: previousTaskId == task.taskId ? nil : previousTaskId)

            if shouldShowOpenClawToast(from: previousStatus, to: task.status) {
                showToast(for: task)
            }
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
                let sentInfo = try await gatewayClient.sendTask(retryDraft, profile: profile)
                task = try stateMachine.transition(task, to: .queued)
                let previousTaskId = task.taskId
                task = try applyGatewaySubmission(sentInfo, to: task)
                task.latestProgress = "Retrying after transient failure"
                upsert(task, replacingTaskId: previousTaskId == task.taskId ? nil : previousTaskId)
                return
            }

            task = try stateMachine.transition(task, to: .needsAttention)
            upsert(task)
            showToast(for: task)
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

    private func upsert(_ task: TaskRecord, replacingTaskId previousTaskId: String? = nil) {
        let idsToReplace = Set([task.taskId, previousTaskId].compactMap { $0 })
        tasks.removeAll { idsToReplace.contains($0.taskId) }
        tasks.insert(task, at: 0)
        persistAsync()
    }

    private func applyGatewaySubmission(_ sentInfo: SentTaskInfo, to task: TaskRecord) throws -> TaskRecord {
        var updated = task
        updated.taskId = sentInfo.taskId
        if let sessionId = sentInfo.sessionId {
            updated.sessionId = sessionId
        }
        if let runId = sentInfo.runId {
            updated.runId = runId
        }
        return try transitionIfNeeded(updated, to: sentInfo.status)
    }

    private func transitionIfNeeded(_ task: TaskRecord, to status: TaskStatus) throws -> TaskRecord {
        guard task.status != status else {
            var updated = task
            updated.updatedAt = Date()
            return updated
        }

        if task.status == .queued && (status == .needsInput || status == .completed) {
            let running = try transitionIfNeeded(task, to: .running)
            return try transitionIfNeeded(running, to: status)
        }

        if task.status == .needsInput && status == .completed {
            let running = try transitionIfNeeded(task, to: .running)
            return try transitionIfNeeded(running, to: status)
        }

        return try stateMachine.transition(task, to: status)
    }

    private func taskMatching(event: GatewayEventEnvelope) -> TaskRecord? {
        tasks.first { task in
            if let taskId = event.taskId, task.taskId == taskId {
                return true
            }
            if let runId = event.runId, task.runId == runId || task.taskId == runId {
                return true
            }
            if let sessionId = event.sessionId, task.sessionId == sessionId {
                return true
            }
            return false
        }
    }

    private enum GatewayTaskEventStatus {
        case progress(String?)
        case needsInput(String?)
        case completed(String?)
        case failed(String)
        case canceled
        case ignored(String?)
    }

    private func eventStatus(for event: GatewayEventEnvelope) -> GatewayTaskEventStatus {
        switch event.eventType {
        case "progress", "run_progress":
            return .progress(event.payload["message"])
        case "needs_input", "question":
            return .needsInput(event.payload["question"] ?? event.payload["prompt"])
        case "completed", "done":
            return .completed(event.payload["message"] ?? event.payload["summary"])
        case "failed", "error":
            return .failed(event.payload["error"] ?? event.payload["message"] ?? "Run failed")
        case "canceled":
            return .canceled
        case "agent":
            return agentEventStatus(payload: event.payload)
        case "chat":
            return chatEventStatus(payload: event.payload)
        case "exec.approval.requested":
            return .needsInput(approvalPrompt(payload: event.payload))
        case "exec.approval.resolved":
            let decision = event.payload["decision"]?.lowercased()
            if decision == "deny" {
                return .failed("Approval denied")
            }
            return .progress("Approval resolved")
        default:
            return .ignored(event.payload["message"])
        }
    }

    private func agentEventStatus(payload: [String: String]) -> GatewayTaskEventStatus {
        let stream = payload["stream"]?.lowercased()
        let phase = payload["phase"]?.lowercased()

        if stream == "lifecycle" {
            switch phase {
            case "start":
                return .progress(payload["summary"] ?? "Working")
            case "end":
                if payload["aborted"]?.lowercased() == "true" {
                    return .canceled
                }
                return .completed(payload["summary"])
            case "error":
                return .failed(payload["error"] ?? "Run failed")
            default:
                break
            }
        }

        if stream == "assistant" || stream == "tool" {
            return .progress(payload["text"] ?? payload["message"] ?? payload["summary"])
        }

        if let status = payload["status"].flatMap(TaskStatus.fromGateway) {
            switch status {
            case .queued, .running:
                return .progress(payload["message"] ?? payload["summary"])
            case .needsInput:
                return .needsInput(payload["question"] ?? payload["prompt"])
            case .completed:
                return .completed(payload["summary"])
            case .failed, .needsAttention:
                return .failed(payload["error"] ?? payload["message"] ?? "Run failed")
            case .canceled:
                return .canceled
            case .draft:
                return .ignored(nil)
            }
        }

        return .ignored(payload["message"] ?? payload["summary"])
    }

    private func chatEventStatus(payload: [String: String]) -> GatewayTaskEventStatus {
        switch payload["state"]?.lowercased() {
        case "delta":
            return .progress(payload["text"] ?? payload["message"] ?? "Responding")
        case "final":
            return .completed(payload["text"] ?? payload["summary"])
        case "error":
            return .failed(payload["error"] ?? payload["message"] ?? "Run failed")
        case "aborted":
            return .canceled
        default:
            return .ignored(payload["message"] ?? payload["text"])
        }
    }

    private func approvalPrompt(payload: [String: String]) -> String {
        if let command = payload["request.commandArgv"], !command.isEmpty {
            return "Approval required: \(command)"
        }
        if let command = payload["request.command"], !command.isEmpty {
            return "Approval required: \(command)"
        }
        return "Approval required"
    }

    private func apply(state: PersistedState) {
        profiles = state.profiles
        commandTemplateSets = state.commandTemplateSets
        tasks = state.tasks
        routesByProfile = state.routeAliasesByProfile
        settings = state.settings
        archivedTaskIds = state.archivedTaskIds

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
            updatedAt: Date(),
            archivedTaskIds: archivedTaskIds
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

    func showToast(for task: TaskRecord) {
        let display = DisplayTask(from: task, profiles: profiles)
        let toast = NotchToast(
            id: UUID(),
            sourceKind: .openClaw,
            title: task.title,
            status: task.status,
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

    private func shouldShowOpenClawToast(from previousStatus: TaskStatus, to currentStatus: TaskStatus) -> Bool {
        guard previousStatus != currentStatus else { return false }

        switch currentStatus {
        case .running, .needsInput, .completed, .failed, .needsAttention, .canceled:
            return true
        default:
            return false
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
        dismissToast()

        // For OpenClaw tasks, select the task in the expanded view
        if toast.sourceKind == .openClaw {
            let rawId = String(toast.displayTask.id.dropFirst("openclaw-".count))
            focusTask(rawId)
        } else {
            // For external tasks, just expand the notch
            setExpanded(true)
        }
    }

    func handleToastLongHover() {
        guard activeToast != nil else { return }
        dismissToast()
        setExpanded(true)
    }

    private func startExternalTaskMonitoring() async {
        Self.log.info("Starting external task monitoring")
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
            guard ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: snapshot) else {
                continue
            }

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

        externalSnapshots = new
    }
}
