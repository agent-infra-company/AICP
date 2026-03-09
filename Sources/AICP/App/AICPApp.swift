import AppKit
import SwiftUI

@main
struct AICPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppRuntimeEnvironment.current

    var body: some Scene {
        Settings {
            if environment.isBundledApp {
                SettingsRootView(core: appDelegate.core)
            } else {
                VStack(spacing: 10) {
                    Text("AICP is running in `swift run` mode.")
                    Text("Menu bar, onboarding, and notification features require launching the app bundle.")
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(minWidth: 520, minHeight: 140)
            }
        }

        MenuBarExtra("AICP", systemImage: "capsule.tophalf.filled", isInserted: .constant(environment.supportsMenuBarExtra)) {
            Button("Open Companion") {
                appDelegate.core.setExpanded(true)
            }

            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
