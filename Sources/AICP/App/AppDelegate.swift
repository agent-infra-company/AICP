import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let core: ControlPlaneCore
    private let aggregator: TaskSourceAggregator
    private let environment = AppRuntimeEnvironment.current
    // V2 onboarding reset migration key – kept for reference but migration is complete.
    // private static let onboardingResetFlagKey = "AICP.didResetOnboardingForV2"

    private var shellController: NotchShellController?
    private var onboardingController: OnboardingWindowController?
    private var unbundledDebugWindow: NSWindow?
    private var settingsWindowController: NSWindowController?

    override init() {
        let secretStore = SecretStoreFactory.create(service: "com.aicp.app")
        let keyProvider = KeychainSymmetricKeyProvider(secretStore: secretStore)
        let persistenceStore = EncryptedPersistenceStore(keyProvider: keyProvider)
        let gatewayClient = OpenClawGatewayClient(secretStore: secretStore)
        let runtimeManager = DefaultRuntimeManager(commandExecutor: ShellCommandExecutor())
        let notificationService = UserNotificationService()
        let telemetryManager = LocalTelemetryManager()
        let loginItemManager = LoginItemManager()
        let retentionManager = RetentionScheduler()

        let aggregator = TaskSourceAggregator()
        self.aggregator = aggregator

        self.core = ControlPlaneCore(
            gatewayClient: gatewayClient,
            runtimeManager: runtimeManager,
            persistenceStore: persistenceStore,
            notificationService: notificationService,
            telemetryManager: telemetryManager,
            loginItemManager: loginItemManager,
            retentionManager: retentionManager,
            taskSourceAggregator: aggregator,
            secretStore: secretStore
        )

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up temp scripts from previous sessions.
        Task { await CLISessionLauncher().cleanupStaleTempScripts() }

        // `swift run` launches an unbundled process.
        guard environment.supportsOnboarding else {
            Task { @MainActor in
                await registerTaskSources()
                await core.bootstrap()
                // Full onboarding is unstable in unbundled runs; open notch shell directly.
                showNotchShell()
                showUnbundledDebugWindow()
            }
            return
        }
        if environment.supportsNotifications {
            UNUserNotificationCenter.current().delegate = self
        }

        Task { @MainActor in
            await registerTaskSources()
            await core.bootstrap()

            if !core.settings.hasCompletedOnboarding {
                onboardingController = OnboardingWindowController(core: core)
                onboardingController?.showIfNeeded { [weak self] in
                    guard let self else { return }
                    showNotchShell()
                    // Auto-expand so the user sees the control plane after onboarding
                    self.core.setExpanded(true)
                }
            } else {
                showNotchShell()
            }
        }
    }

    private func registerTaskSources() async {
        await aggregator.register(ConductorTaskSource())
        await aggregator.register(ClaudeCodeTaskSource())
        await aggregator.register(CodexTaskSource())
        await aggregator.register(ClaudeDesktopTaskSource())
        await aggregator.register(CursorTaskSource())
        await aggregator.register(WebAIChatTaskSource())
    }

    private func showNotchShell() {
        if shellController == nil {
            shellController = NotchShellController(core: core)
        }
        shellController?.show()
    }

    // V2 migration removed: resetOnboardingIfNeeded() was resetting hasCompletedOnboarding
    // on every launch when the UserDefaults flag failed to persist (e.g. unbundled runs,
    // domain changes). The migration is complete so the reset is no longer needed.

    func openSettingsWindow() {
        if let window = settingsWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AICP Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AICP.SettingsWindow")
        window.contentView = NSHostingView(rootView: SettingsRootView(core: core))

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showUnbundledDebugWindow() {
        let content = VStack(spacing: 10) {
            Text("AICP is running in `swift run` mode.")
            Text("The notch control plane is loaded. Menu bar, full onboarding, and notification permissions require launching the app bundle.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 140)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AICP (swift run)"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content)

        unbundledDebugWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
