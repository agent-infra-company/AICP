import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let core: CompanionCore

    private var shellController: NotchShellController?

    override init() {
        let secretStore = KeychainSecretStore(service: "com.clawdbot.notch")
        let keyProvider = KeychainSymmetricKeyProvider(secretStore: secretStore)
        let persistenceStore = EncryptedPersistenceStore(keyProvider: keyProvider)
        let gatewayClient = OpenClawGatewayClient(secretStore: secretStore)
        let runtimeManager = DefaultRuntimeManager(commandExecutor: ShellCommandExecutor())
        let notificationService = UserNotificationService()
        let telemetryManager = LocalTelemetryManager()
        let loginItemManager = LoginItemManager()
        let retentionManager = RetentionScheduler()

        self.core = CompanionCore(
            gatewayClient: gatewayClient,
            runtimeManager: runtimeManager,
            persistenceStore: persistenceStore,
            notificationService: notificationService,
            telemetryManager: telemetryManager,
            loginItemManager: loginItemManager,
            retentionManager: retentionManager
        )

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            self.shellController = NotchShellController(core: core)
            shellController?.show()
            await core.bootstrap()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let taskId = response.notification.request.content.userInfo["taskId"] as? String {
            Task { @MainActor in
                core.focusTask(taskId)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
