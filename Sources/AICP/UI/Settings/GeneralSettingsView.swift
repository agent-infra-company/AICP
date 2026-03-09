import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General")
                .font(.title2.weight(.semibold))

            GroupBox("Behavior") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Launch at login", isOn: settingsBinding(\.launchAtLogin))
                    Toggle("Show in fullscreen spaces", isOn: settingsBinding(\.showInFullscreen))
                    Toggle("Hide in screen recordings", isOn: settingsBinding(\.hideInScreenRecording))
                    Toggle("Primary display only", isOn: settingsBinding(\.primaryDisplayOnly))
                }
                .padding(8)
            }

            GroupBox("Data") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Anonymous telemetry", isOn: settingsBinding(\.telemetryOptIn))

                    Stepper(
                        "History retention: \(core.settings.retentionDays) days",
                        value: Binding(
                            get: { core.settings.retentionDays },
                            set: { newValue in
                                core.updateSetting { $0.retentionDays = min(max(newValue, 7), 365) }
                            }
                        ),
                        in: 7...365
                    )
                }
                .padding(8)
            }

            GroupBox("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 10) {
                    shortcutRow(keys: "Hover notch area", action: "Expand companion")
                    shortcutRow(keys: "Click outside", action: "Collapse companion")
                    shortcutRow(keys: "Return", action: "Submit prompt / send follow-up")
                    shortcutRow(keys: "Esc", action: "Cancel current input")
                }
                .padding(8)
            }
        }
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer()
            Text(action)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { core.settings[keyPath: keyPath] },
            set: { newValue in core.updateSetting { $0[keyPath: keyPath] = newValue } }
        )
    }
}
