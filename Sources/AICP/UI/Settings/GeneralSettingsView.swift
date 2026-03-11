import AppKit
import SwiftUI
@preconcurrency import UserNotifications

struct GeneralSettingsView: View {
    @ObservedObject var core: ControlPlaneCore
    @State private var notificationsAuthorized = false
    @State private var checkingNotifications = false

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Launch at login", isOn: settingsBinding(\.launchAtLogin))
                Toggle("Show in fullscreen spaces", isOn: settingsBinding(\.showInFullscreen))
                Toggle("Hide in screen recordings", isOn: settingsBinding(\.hideInScreenRecording))
                Toggle("Primary display only", isOn: settingsBinding(\.primaryDisplayOnly))
            }

            Section {
                HStack {
                    Text("Notifications")
                    Spacer()
                    if !AppRuntimeEnvironment.current.supportsNotifications {
                        Text("Requires app bundle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if checkingNotifications {
                        ProgressView()
                            .controlSize(.small)
                    } else if notificationsAuthorized {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        Button("Enable") {
                            Task {
                                checkingNotifications = true
                                let result = await core.requestNotificationAuthorization()
                                if result {
                                    notificationsAuthorized = true
                                } else {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                checkingNotifications = false
                            }
                        }
                        .controlSize(.small)

                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                if !AppRuntimeEnvironment.current.supportsNotifications {
                    Text("Run `make install` and launch from /Applications to enable notifications.")
                } else if !notificationsAuthorized && !checkingNotifications {
                    Text("If AICP doesn't appear in System Settings, rebuild with `make install`.")
                }
            }

            Section {
                Toggle("OpenClaw Gateway", isOn: Binding(
                    get: { core.settings.openClawEnabled },
                    set: { newValue in
                        Task {
                            if newValue {
                                await core.enableOpenClaw()
                            } else {
                                await core.disableOpenClaw()
                            }
                        }
                    }
                ))
            } header: {
                Text("Integrations")
            } footer: {
                Text("Enable to use a local OpenClaw gateway for task routing. Disable if you only use Claude Code or Codex directly.")
            }

            Section("Data") {
                Toggle("Anonymous telemetry", isOn: settingsBinding(\.telemetryOptIn))

                HStack {
                    Text("History retention")
                    Spacer()
                    Text("\(core.settings.retentionDays) days")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper(
                        "",
                        value: Binding(
                            get: { core.settings.retentionDays },
                            set: { newValue in
                                core.updateSetting { $0.retentionDays = min(max(newValue, 7), 365) }
                            }
                        ),
                        in: 7...365
                    )
                    .labelsHidden()
                    .frame(width: 80)
                }
            }

            Section("Keyboard Shortcuts") {
                shortcutRow(keys: "Hover notch", action: "Expand control plane")
                shortcutRow(keys: "Click outside", action: "Collapse")
                shortcutRow(keys: "Return ↩", action: "Submit prompt")
                shortcutRow(keys: "Esc", action: "Cancel input")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .task {
            await checkNotificationStatus()
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(action)
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
