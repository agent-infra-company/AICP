import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var core: CompanionCore

    @State private var selectedProfileId: UUID?
    @State private var selectedTemplateId: UUID?

    var body: some View {
        Form {
            generalSection
            profileSection
            commandTemplateSection
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            selectedProfileId = core.selectedProfile?.id ?? core.profiles.first?.id
            selectedTemplateId = core.commandTemplateSets.first?.id
        }
        .alert(
            core.pendingRuntimeOperation?.title ?? "",
            isPresented: Binding(
                get: { core.pendingRuntimeOperation != nil },
                set: { value in
                    if !value {
                        core.clearPendingRuntimeAction()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                core.clearPendingRuntimeAction()
            }
            Button("Confirm", role: .destructive) {
                Task { await core.confirmPendingRuntimeAction() }
            }
        } message: {
            Text(core.pendingRuntimeOperation?.message ?? "")
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { core.settings.launchAtLogin },
                    set: { newValue in
                        core.updateSetting { $0.launchAtLogin = newValue }
                    }
                )
            )

            Toggle(
                "Show in fullscreen",
                isOn: Binding(
                    get: { core.settings.showInFullscreen },
                    set: { newValue in
                        core.updateSetting { $0.showInFullscreen = newValue }
                    }
                )
            )

            Toggle(
                "Hide in screen recordings",
                isOn: Binding(
                    get: { core.settings.hideInScreenRecording },
                    set: { newValue in
                        core.updateSetting { $0.hideInScreenRecording = newValue }
                    }
                )
            )

            Toggle(
                "Opt-in anonymous telemetry",
                isOn: Binding(
                    get: { core.settings.telemetryOptIn },
                    set: { newValue in
                        core.updateSetting { $0.telemetryOptIn = newValue }
                    }
                )
            )

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
    }

    private var profileSection: some View {
        Section("Profiles") {
            HStack {
                Picker(
                    "Selected Profile",
                    selection: Binding(
                        get: { selectedProfileId ?? core.selectedProfile?.id ?? core.profiles.first?.id ?? UUID() },
                        set: { newValue in
                            selectedProfileId = newValue
                            core.selectProfile(newValue)
                        }
                    )
                ) {
                    ForEach(core.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                Button("Add Local") {
                    guard let templateId = core.commandTemplateSets.first?.id else { return }
                    let profile = ProfileConfig.defaultLocal(commandTemplateSetId: templateId)
                    core.upsertProfile(profile)
                    selectedProfileId = profile.id
                }

                Button("Add Remote") {
                    guard let templateId = core.commandTemplateSets.first?.id else { return }
                    let remote = ProfileConfig(
                        id: UUID(),
                        name: "Remote OpenClaw",
                        kind: .remote,
                        gatewayURL: URL(string: "https://example-gateway.local")!,
                        authMode: .bearerToken,
                        tokenRef: "remote.gateway.token",
                        sshRef: "user@remote-host",
                        commandTemplateSetId: templateId,
                        enabled: true
                    )
                    core.upsertProfile(remote)
                    selectedProfileId = remote.id
                }
            }

            if let profile = currentProfile {
                ProfileEditorRow(
                    profile: profile,
                    templateSets: core.commandTemplateSets,
                    onSave: { core.upsertProfile($0) }
                )
            }
        }
    }

    private var commandTemplateSection: some View {
        Section("Command Templates") {
            Picker(
                "Template Set",
                selection: Binding(
                    get: { selectedTemplateId ?? core.commandTemplateSets.first?.id ?? UUID() },
                    set: { selectedTemplateId = $0 }
                )
            ) {
                ForEach(core.commandTemplateSets) { set in
                    Text(set.name).tag(set.id)
                }
            }

            if let set = currentTemplateSet {
                CommandTemplateEditor(set: set) { updated in
                    core.upsertCommandTemplateSet(updated)
                }
            }

            Button("Add Template Set") {
                let newSet = CommandTemplateSet(
                    id: UUID(),
                    name: "Template \(core.commandTemplateSets.count + 1)",
                    startCmd: "openclaw gateway start --port {{port}}",
                    stopCmd: "openclaw gateway stop",
                    restartCmd: "openclaw gateway restart --port {{port}}",
                    statusCmd: "openclaw gateway status",
                    allowedPlaceholders: ["host", "port", "gateway_url", "profile_name"]
                )
                core.upsertCommandTemplateSet(newSet)
                selectedTemplateId = newSet.id
            }
        }
    }

    private var currentProfile: ProfileConfig? {
        guard let selectedProfileId else {
            return core.selectedProfile
        }
        return core.profiles.first(where: { $0.id == selectedProfileId })
    }

    private var currentTemplateSet: CommandTemplateSet? {
        guard let selectedTemplateId else {
            return core.commandTemplateSets.first
        }
        return core.commandTemplateSets.first(where: { $0.id == selectedTemplateId })
    }
}

private struct ProfileEditorRow: View {
    @State var profile: ProfileConfig
    let templateSets: [CommandTemplateSet]
    let onSave: (ProfileConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $profile.name)

            TextField(
                "Gateway URL",
                text: Binding(
                    get: { profile.gatewayURL.absoluteString },
                    set: { profile.gatewayURL = URL(string: $0) ?? profile.gatewayURL }
                )
            )

            Picker("Kind", selection: $profile.kind) {
                Text("Local").tag(ProfileKind.local)
                Text("Remote").tag(ProfileKind.remote)
            }

            Picker("Auth", selection: $profile.authMode) {
                Text("None").tag(ProfileAuthMode.none)
                Text("Bearer token").tag(ProfileAuthMode.bearerToken)
            }

            TextField(
                "Token reference",
                text: Binding(
                    get: { profile.tokenRef ?? "" },
                    set: { profile.tokenRef = $0.isEmpty ? nil : $0 }
                )
            )

            TextField(
                "SSH reference (remote)",
                text: Binding(
                    get: { profile.sshRef ?? "" },
                    set: { profile.sshRef = $0.isEmpty ? nil : $0 }
                )
            )

            Picker("Template Set", selection: $profile.commandTemplateSetId) {
                ForEach(templateSets) { set in
                    Text(set.name).tag(set.id)
                }
            }

            Toggle("Enabled", isOn: $profile.enabled)

            HStack {
                Spacer()
                Button("Save Profile") {
                    onSave(profile)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CommandTemplateEditor: View {
    @State var set: CommandTemplateSet
    let onSave: (CommandTemplateSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Template name", text: $set.name)
            TextField("Start command", text: $set.startCmd)
            TextField("Stop command", text: $set.stopCmd)
            TextField("Restart command", text: $set.restartCmd)
            TextField("Status command", text: $set.statusCmd)

            TextField(
                "Allowed placeholders (comma separated)",
                text: Binding(
                    get: { set.allowedPlaceholders.joined(separator: ",") },
                    set: {
                        set.allowedPlaceholders = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                )
            )

            HStack {
                Spacer()
                Button("Save Template") {
                    onSave(set)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
