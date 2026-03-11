import Foundation
import XCTest
@testable import AICP

@MainActor
final class ControlPlaneCoreSecureStorageTests: XCTestCase {
    func testRequestSecureStorageAccessDelegatesToInteractiveSecretStore() async {
        let secretStore = SecureStorageStubSecretStore()
        let core = makeCore(secretStore: secretStore)

        let granted = await core.requestSecureStorageAccess()

        XCTAssertTrue(granted)
        XCTAssertTrue(secretStore.didRequestInteractiveAccess)
        XCTAssertNil(core.lastErrorBanner)
    }

    func testRequestSecureStorageAccessSurfacesErrors() async {
        let secretStore = SecureStorageStubSecretStore(requestError: SecureStorageStubError.synthetic)
        let core = makeCore(secretStore: secretStore)

        let granted = await core.requestSecureStorageAccess()

        XCTAssertFalse(granted)
        XCTAssertEqual(core.lastErrorBanner, "Keychain access failed: synthetic keychain failure")
    }

    private func makeCore(secretStore: SecretStoring) -> ControlPlaneCore {
        ControlPlaneCore(
            gatewayClient: SecureStorageStubGatewayClient(),
            runtimeManager: SecureStorageStubRuntimeManager(),
            persistenceStore: SecureStorageStubPersistenceStore(),
            notificationService: SecureStorageStubNotificationService(),
            telemetryManager: SecureStorageStubTelemetryManager(),
            loginItemManager: SecureStorageStubLoginItemManager(),
            retentionManager: SecureStorageStubRetentionManager(),
            taskSourceAggregator: TaskSourceAggregator(),
            secretStore: secretStore
        )
    }
}

private enum SecureStorageStubError: LocalizedError {
    case synthetic

    var errorDescription: String? {
        "synthetic keychain failure"
    }
}

private final class SecureStorageStubSecretStore: SecretStoring, InteractiveSecureStorageControlling, @unchecked Sendable {
    private let requestError: Error?
    private(set) var didRequestInteractiveAccess = false

    init(requestError: Error? = nil) {
        self.requestError = requestError
    }

    func secret(for key: String) throws -> String? { nil }

    func setSecret(_ value: String, for key: String) throws {}

    func removeSecret(for key: String) throws {}

    func requestInteractivePrimaryAccess() throws -> Bool {
        didRequestInteractiveAccess = true
        if let requestError {
            throw requestError
        }
        return true
    }
}

private actor SecureStorageStubGatewayClient: GatewayClient {
    func connect(profile: ProfileConfig) async throws {}

    func disconnect(profileId: UUID) async {}

    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo] { [] }

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

private actor SecureStorageStubRuntimeManager: RuntimeManager {
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

private actor SecureStorageStubPersistenceStore: PersistenceStore {
    func loadState() async throws -> PersistedState {
        PersistedState.bootstrap()
    }

    func saveState(_ state: PersistedState) async throws {}
}

private final class SecureStorageStubNotificationService: NotificationService, @unchecked Sendable {
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

private final class SecureStorageStubTelemetryManager: TelemetryManaging {
    func setOptIn(_ enabled: Bool) {}
    func record(_ event: TelemetryEvent) {}
}

private final class SecureStorageStubLoginItemManager: LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws {}
}

private final class SecureStorageStubRetentionManager: RetentionManaging {
    func schedule(retentionDays: Int, onTick: @escaping @Sendable () -> Void) {}
}
