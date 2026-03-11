import Foundation
import XCTest
@testable import AICP

@MainActor
final class ControlPlaneCoreSubmissionTests: XCTestCase {
    func testSubmitPromptRekeysTaskWhenGatewayReturnsCanonicalTaskID() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(
            sendTaskResponses: [
                .success(
                    SentTaskInfo(
                        taskId: "server-task-1",
                        sessionId: "session-1",
                        runId: "run-1",
                        status: .running
                    )
                )
            ]
        )
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore
        )

        await core.bootstrap()
        core.selectCLI(.openClaw)
        core.isExpanded = true
        core.composePrompt = "Ship the release notes"

        await core.submitPrompt()

        XCTAssertEqual(core.tasks.count, 1)
        XCTAssertEqual(core.tasks.first?.taskId, "server-task-1")
        XCTAssertEqual(core.tasks.first?.sessionId, "session-1")
        XCTAssertEqual(core.tasks.first?.runId, "run-1")
        XCTAssertEqual(core.tasks.first?.status, .running)
        XCTAssertEqual(core.activeToast?.sourceKind, .openClaw)
        XCTAssertEqual(core.activeToast?.status, .running)
        XCTAssertFalse(core.isExpanded)
    }

    func testRetryPathRekeysTaskWhenRetryReceivesCanonicalTaskID() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(
            sendTaskResponses: [
                .failure(StubError.syntheticFailure),
                .success(
                    SentTaskInfo(
                        taskId: "server-task-retry",
                        sessionId: "session-retry",
                        runId: "run-retry",
                        status: .queued
                    )
                )
            ]
        )
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore
        )

        await core.bootstrap()
        core.selectCLI(.openClaw)
        core.composePrompt = "Retry this task"

        await core.submitPrompt()

        XCTAssertEqual(core.tasks.count, 1)
        XCTAssertEqual(core.tasks.first?.taskId, "server-task-retry")
        XCTAssertEqual(core.tasks.first?.sessionId, "session-retry")
        XCTAssertEqual(core.tasks.first?.runId, "run-retry")
        XCTAssertEqual(core.tasks.first?.retryCount, 1)
        XCTAssertEqual(core.tasks.first?.status, .queued)
        XCTAssertEqual(core.tasks.first?.latestProgress, "Retrying after transient failure")
    }

    func testModernGatewayEventsUpdateTaskWithoutLegacyTaskIdentifier() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(
            sendTaskResponses: [
                .success(
                    SentTaskInfo(
                        taskId: "run-42",
                        sessionId: "agent:main:main",
                        runId: "run-42",
                        status: .queued
                    )
                )
            ]
        )
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore
        )

        await core.bootstrap()
        core.selectCLI(.openClaw)
        core.composePrompt = "Summarize the deployment state"

        await core.submitPrompt()
        await gatewayClient.emit(
            GatewayEventEnvelope(
                source: "Local OpenClaw",
                sessionId: "agent:main:main",
                runId: "run-42",
                taskId: nil,
                eventType: "agent",
                payload: [
                    "stream": "lifecycle",
                    "phase": "start",
                    "summary": "Agent started"
                ]
            )
        )
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(core.tasks.first?.status, .running)
        XCTAssertEqual(core.tasks.first?.latestProgress, "Agent started")

        await gatewayClient.emit(
            GatewayEventEnvelope(
                source: "Local OpenClaw",
                sessionId: "agent:main:main",
                runId: "run-42",
                taskId: nil,
                eventType: "chat",
                payload: [
                    "state": "final",
                    "text": "Deployment looks healthy."
                ]
            )
        )
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(core.tasks.first?.status, .completed)
        XCTAssertEqual(core.tasks.first?.runId, "run-42")
        XCTAssertEqual(core.tasks.first?.sessionId, "agent:main:main")
    }

    func testApprovalEventMovesTaskToNeedsInputUsingSessionKeyCorrelation() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(
            sendTaskResponses: [
                .success(
                    SentTaskInfo(
                        taskId: "run-approval",
                        sessionId: "agent:main:main",
                        runId: "run-approval",
                        status: .running
                    )
                )
            ]
        )
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore
        )

        await core.bootstrap()
        core.selectCLI(.openClaw)
        core.composePrompt = "Run the deployment command"

        await core.submitPrompt()
        await gatewayClient.emit(
            GatewayEventEnvelope(
                source: "Local OpenClaw",
                sessionId: "agent:main:main",
                runId: "run-approval",
                taskId: nil,
                eventType: "exec.approval.requested",
                payload: [
                    "request.sessionKey": "agent:main:main",
                    "request.commandArgv": "deploy --prod"
                ]
            )
        )
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, core.tasks.first?.status != .needsInput {
            await Task.yield()
        }

        XCTAssertEqual(core.tasks.first?.status, .needsInput)
        XCTAssertEqual(core.tasks.first?.needsInputPrompt, "Approval required: deploy --prod")
    }

    func testCollapseIsAllowedWhileSubmitting() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(sendTaskResponses: [])
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore
        )

        await core.bootstrap()
        core.isExpanded = true
        core.isSubmitting = true

        core.setExpanded(false)

        XCTAssertFalse(core.isExpanded)
    }

    func testSubmitPromptSkipsRuntimeSSHCheckForRemoteWithoutSSHReference() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrapWithOpenClaw())
        let gatewayClient = StubGatewayClient(
            sendTaskResponses: [
                .success(
                    SentTaskInfo(
                        taskId: "remote-task-1",
                        sessionId: "agent:main:main",
                        runId: "remote-task-1",
                        status: .running
                    )
                )
            ]
        )
        let runtimeManager = MissingSSHRuntimeManager()
        let core = makeCore(
            gatewayClient: gatewayClient,
            persistenceStore: persistenceStore,
            runtimeManager: runtimeManager
        )

        await core.bootstrap()
        guard var profile = core.profiles.first else {
            XCTFail("Expected bootstrap profile")
            return
        }
        profile.kind = .remote
        profile.gatewayURL = URL(string: "https://example-gateway.local")!
        profile.sshRef = nil
        core.upsertProfile(profile)
        core.selectProfile(profile.id)
        core.selectCLI(.openClaw)
        core.composePrompt = "Send to remote gateway"

        await core.submitPrompt()

        let statusCalls = await runtimeManager.statusCallCount()
        XCTAssertEqual(statusCalls, 0)
        XCTAssertEqual(core.tasks.first?.taskId, "remote-task-1")
        XCTAssertEqual(core.tasks.first?.status, .running)
    }

    private func makeCore(
        gatewayClient: GatewayClient,
        persistenceStore: PersistenceStore,
        runtimeManager: RuntimeManager = StubRuntimeManager()
    ) -> ControlPlaneCore {
        ControlPlaneCore(
            gatewayClient: gatewayClient,
            runtimeManager: runtimeManager,
            persistenceStore: persistenceStore,
            notificationService: StubNotificationService(),
            telemetryManager: StubTelemetryManager(),
            loginItemManager: StubLoginItemManager(),
            retentionManager: StubRetentionManager(),
            taskSourceAggregator: TaskSourceAggregator()
        )
    }
}

private enum StubError: Error {
    case syntheticFailure
}

private actor StubGatewayClient: GatewayClient {
    private var sendTaskResponses: [Result<SentTaskInfo, Error>]
    private let eventStream: AsyncStream<GatewayEventEnvelope>
    private let eventContinuation: AsyncStream<GatewayEventEnvelope>.Continuation

    init(sendTaskResponses: [Result<SentTaskInfo, Error>]) {
        self.sendTaskResponses = sendTaskResponses
        var continuation: AsyncStream<GatewayEventEnvelope>.Continuation?
        self.eventStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        self.eventContinuation = continuation!
    }

    func connect(profile: ProfileConfig) async throws {}

    func disconnect(profileId: UUID) async {}

    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo] {
        [RouteInfo(id: "default", displayName: "Default", metadata: [:])]
    }

    func sendTask(_ draft: TaskDraft, profile: ProfileConfig) async throws -> SentTaskInfo {
        let result = sendTaskResponses.removeFirst()
        return try result.get()
    }

    func answerFollowUp(task: TaskRecord, answer: String, profile: ProfileConfig) async throws {}

    func subscribeEvents(profileId: UUID) async -> AsyncStream<GatewayEventEnvelope> {
        eventStream
    }

    func emit(_ event: GatewayEventEnvelope) {
        eventContinuation.yield(event)
    }
}

private actor StubRuntimeManager: RuntimeManager {
    func updateConfiguration(profiles: [ProfileConfig], templateSets: [CommandTemplateSet]) async {}

    func start(profileId: UUID) async throws -> RuntimeStatus {
        healthyStatus()
    }

    func stop(profileId: UUID) async throws -> RuntimeStatus {
        RuntimeStatus(isHealthy: false, detail: "Stopped", checkedAt: Date())
    }

    func restart(profileId: UUID) async throws -> RuntimeStatus {
        healthyStatus()
    }

    func status(profileId: UUID) async throws -> RuntimeStatus {
        healthyStatus()
    }

    private func healthyStatus() -> RuntimeStatus {
        RuntimeStatus(isHealthy: true, detail: "Healthy", checkedAt: Date())
    }
}

private actor MissingSSHRuntimeManager: RuntimeManager {
    private var statusCalls = 0

    func updateConfiguration(profiles: [ProfileConfig], templateSets: [CommandTemplateSet]) async {}

    func start(profileId: UUID) async throws -> RuntimeStatus {
        throw RuntimeManagerError.missingSSHReference
    }

    func stop(profileId: UUID) async throws -> RuntimeStatus {
        throw RuntimeManagerError.missingSSHReference
    }

    func restart(profileId: UUID) async throws -> RuntimeStatus {
        throw RuntimeManagerError.missingSSHReference
    }

    func status(profileId: UUID) async throws -> RuntimeStatus {
        statusCalls += 1
        throw RuntimeManagerError.missingSSHReference
    }

    func statusCallCount() -> Int {
        statusCalls
    }
}

private actor StubPersistenceStore: PersistenceStore {
    private let state: PersistedState

    init(state: PersistedState) {
        self.state = state
    }

    func loadState() async throws -> PersistedState {
        state
    }

    func saveState(_ state: PersistedState) async throws {}
}

private final class StubNotificationService: NotificationService, @unchecked Sendable {
    func prepare() async throws {}
    func requestAuthorization() async throws -> Bool { false }
    func sendTaskNeedsInput(_ task: TaskRecord) async {}
    func sendTaskCompleted(_ task: TaskRecord) async {}
    func sendTaskFailed(_ task: TaskRecord) async {}
    func sendExternalTaskStarted(_ snapshot: ExternalTaskSnapshot) async {}
    func sendExternalTaskNeedsInput(_ snapshot: ExternalTaskSnapshot) async {}
    func sendExternalTaskCompleted(_ snapshot: ExternalTaskSnapshot) async {}
    func sendExternalTaskFailed(_ snapshot: ExternalTaskSnapshot) async {}
}

private final class StubTelemetryManager: TelemetryManaging {
    func setOptIn(_ enabled: Bool) {}
    func record(_ event: TelemetryEvent) {}
}

private final class StubLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

private final class StubRetentionManager: RetentionManaging {
    func schedule(retentionDays: Int, onTick: @escaping @Sendable () -> Void) {}
}
