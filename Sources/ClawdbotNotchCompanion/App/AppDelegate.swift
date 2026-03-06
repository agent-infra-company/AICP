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

        let aggregator = TaskSourceAggregator()

        self.core = CompanionCore(
            gatewayClient: gatewayClient,
            runtimeManager: runtimeManager,
            persistenceStore: persistenceStore,
            notificationService: notificationService,
            telemetryManager: telemetryManager,
            loginItemManager: loginItemManager,
            retentionManager: retentionManager,
            taskSourceAggregator: aggregator
        )

        super.init()

        Task {
            await aggregator.register(ConductorTaskSource())
            await aggregator.register(ClaudeCodeTaskSource())
            await aggregator.register(CodexTaskSource())
            await aggregator.register(ClaudeDesktopTaskSource())
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

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
        let userInfo = response.notification.request.content.userInfo

        if let sourceKindRaw = userInfo["sourceKind"] as? String,
           let _ = TaskSourceKind(rawValue: sourceKindRaw) {
            // External task notification — deep link to source app
            if let deepLinkStr = userInfo["deepLinkURL"] as? String,
               !deepLinkStr.isEmpty,
               let url = URL(string: deepLinkStr) {
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            }
        } else if let taskId = userInfo["taskId"] as? String {
            // OpenClaw task notification — focus in panel
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
