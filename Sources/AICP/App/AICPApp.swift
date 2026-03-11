import AppKit
import SwiftUI

@main
struct AICPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppRuntimeEnvironment.current

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: -1) {
                Text("AI")
                Text("CP")
            }
            .font(.system(size: 6.5, weight: .bold, design: .rounded))
            .lineLimit(1)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .frame(width: 4, height: 12)
        }
        .foregroundStyle(.primary)
        .frame(width: 18, height: 14, alignment: .center)
        .accessibilityLabel("AICP")
    }

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

        MenuBarExtra(isInserted: .constant(environment.supportsMenuBarExtra)) {
            Button("Open Control Plane") {
                appDelegate.core.setExpanded(true)
            }

            Button("Settings") {
                appDelegate.openSettingsWindow()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)
    }
}
