import AppKit
import SwiftUI

@main
struct ClawdbotNotchCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView(core: appDelegate.core)
        }

        MenuBarExtra("Clawdbot", systemImage: "capsule.tophalf.filled") {
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
