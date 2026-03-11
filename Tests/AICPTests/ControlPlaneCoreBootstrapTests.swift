import Foundation
import XCTest
@testable import AICP

@MainActor
final class ControlPlaneCoreBootstrapTests: XCTestCase {
    func testBootstrapFallsBackToDefaultLocalStateWhenPersistenceLoadFails() async {
        let persistenceStore = FailingPersistenceStore()
        let core = ControlPlaneCore(
            gatewayClient: BootstrapStubGatewayClient(),
            runtimeManager: BootstrapStubRuntimeManager(),
            persistenceStore: persistenceStore,
            notificationService: BootstrapStubNotificationService(),
            telemetryManager: BootstrapStubTelemetryManager(),
            loginItemManager: BootstrapStubLoginItemManager(),
            retentionManager: BootstrapStubRetentionManager(),
            taskSourceAggregator: TaskSourceAggregator()
        )

        await core.bootstrap()

        XCTAssertEqual(core.profiles.count, 0)
        XCTAssertFalse(core.availableCLIs.contains(.openClaw))
        XCTAssertFalse(core.settings.openClawEnabled)
        XCTAssertNil(core.settings.selectedProfileId)
        XCTAssertEqual(core.lastErrorBanner, "Failed to load state: synthetic load failure")
        let savedStateCount = await persistenceStore.savedStateCount()
        XCTAssertGreaterThanOrEqual(savedStateCount, 1)
    }
}

private struct BootstrapStubError: LocalizedError {
    var errorDescription: String? { "synthetic load failure" }
}

private actor FailingPersistenceStore: PersistenceStore {
    private var savedStates: [PersistedState] = []

    func loadState() async throws -> PersistedState {
        throw BootstrapStubError()
    }

    func saveState(_ state: PersistedState) async throws {
        savedStates.append(state)
    }

    func savedStateCount() -> Int {
        savedStates.count
    }
}

private actor BootstrapStubGatewayClient: GatewayClient {
    func connect(profile: ProfileConfig) async throws {}

    func disconnect(profileId: UUID) async {}

    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo] {
        [RouteInfo(id: "default", displayName: "Default", metadata: [:])]
    }

    func sendTask(_ draft: TaskDraft, profile: ProfileConfig) async throws -> SentTaskInfo {
        SentTaskInfo(taskId: draft.clientTaskId, sessionId: nil, runId: nil, status: .queued)
    }

    func answerFollowUp(task: TaskRecord, answer: String, profile: ProfileConfig) async throws {}

    func subscribeEvents(profileId: UUID) async -> AsyncStream<GatewayEventEnvelope> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

private actor BootstrapStubRuntimeManager: RuntimeManager {
    func updateConfiguration(profiles: [ProfileConfig], templateSets: [CommandTemplateSet]) async {}

    func start(profileId: UUID) async throws -> RuntimeStatus {
        RuntimeStatus(isHealthy: true, detail: "Healthy", checkedAt: Date())
    }

    func stop(profileId: UUID) async throws -> RuntimeStatus {
        RuntimeStatus(isHealthy: false, detail: "Stopped", checkedAt: Date())
    }

    func restart(profileId: UUID) async throws -> RuntimeStatus {
        RuntimeStatus(isHealthy: true, detail: "Healthy", checkedAt: Date())
    }

    func status(profileId: UUID) async throws -> RuntimeStatus {
        RuntimeStatus(isHealthy: true, detail: "Healthy", checkedAt: Date())
    }
}

private final class BootstrapStubNotificationService: NotificationService, @unchecked Sendable {
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

private final class BootstrapStubTelemetryManager: TelemetryManaging {
    func setOptIn(_ enabled: Bool) {}
    func record(_ event: TelemetryEvent) {}
}

private final class BootstrapStubLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

private final class BootstrapStubRetentionManager: RetentionManaging {
    func schedule(retentionDays: Int, onTick: @escaping @Sendable () -> Void) {}
}
