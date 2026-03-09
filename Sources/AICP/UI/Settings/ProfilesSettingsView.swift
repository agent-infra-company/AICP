import SwiftUI

struct ProfilesSettingsView: View {
    @ObservedObject var core: CompanionCore
    @State private var selectedProfileId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Profiles")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
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
                .padding(8)
            }
        }
        .onAppear {
            selectedProfileId = core.selectedProfile?.id ?? core.profiles.first?.id
        }
    }

    private var currentProfile: ProfileConfig? {
        guard let selectedProfileId else {
            return core.selectedProfile
        }
        return core.profiles.first(where: { $0.id == selectedProfileId })
    }
}

struct ProfileEditorRow: View {
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
