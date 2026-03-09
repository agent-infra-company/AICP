import Foundation
import XCTest
@testable import AICP

@MainActor
final class CompanionCoreSubmissionTests: XCTestCase {
    func testSubmitPromptRekeysTaskWhenGatewayReturnsCanonicalTaskID() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrap())
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
        core.composePrompt = "Ship the release notes"

        await core.submitPrompt()

        XCTAssertEqual(core.tasks.count, 1)
        XCTAssertEqual(core.tasks.first?.taskId, "server-task-1")
        XCTAssertEqual(core.tasks.first?.sessionId, "session-1")
        XCTAssertEqual(core.tasks.first?.runId, "run-1")
        XCTAssertEqual(core.tasks.first?.status, .running)
    }

    func testRetryPathRekeysTaskWhenRetryReceivesCanonicalTaskID() async throws {
        let persistenceStore = StubPersistenceStore(state: PersistedState.bootstrap())
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

    private func makeCore(
        gatewayClient: GatewayClient,
        persistenceStore: PersistenceStore
    ) -> CompanionCore {
        CompanionCore(
            gatewayClient: gatewayClient,
            runtimeManager: StubRuntimeManager(),
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

    init(sendTaskResponses: [Result<SentTaskInfo, Error>]) {
        self.sendTaskResponses = sendTaskResponses
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
        AsyncStream { continuation in
            continuation.finish()
        }
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
