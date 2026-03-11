import SwiftUI

struct ProfilesSettingsView: View {
    @ObservedObject var core: ControlPlaneCore
    @State private var selectedProfileId: UUID?

    var body: some View {
        Form {
            if core.commandTemplateSets.isEmpty {
                Section {
                    Label("Create a command template set first.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Active Gateway") {
                    Picker(
                        "Gateway",
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
                    .labelsHidden()

                    HStack(spacing: 8) {
                        Button("Add Local Gateway") { addProfile(kind: .local) }
                        Button("Add Remote Gateway") { addProfile(kind: .remote) }
                    }
                }

                if let profile = currentProfile {
                    ProfileEditorSection(
                        profile: profile,
                        templateSets: core.commandTemplateSets,
                        onSave: { core.upsertProfile($0) },
                        onSaveCredential: { ref, value in
                            core.saveCredential(value, forRef: ref)
                        }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Gateways")
        .onAppear {
            selectedProfileId = core.selectedProfile?.id ?? core.profiles.first?.id
        }
    }

    private func addProfile(kind: ProfileKind) {
        guard let templateId = core.commandTemplateSets.first?.id else { return }
        let profile: ProfileConfig
        if kind == .local {
            profile = ProfileConfig.defaultLocal(commandTemplateSetId: templateId)
        } else {
            profile = ProfileConfig(
                id: UUID(),
                name: "Remote Gateway",
                kind: .remote,
                gatewayURL: URL(string: "https://example-gateway.local")!,
                authMode: .token,
                tokenRef: "remote.gateway.token.\(UUID().uuidString.prefix(8))",
                sshRef: nil,
                commandTemplateSetId: templateId,
                enabled: true
            )
        }
        core.upsertProfile(profile)
        selectedProfileId = profile.id
    }

    private var currentProfile: ProfileConfig? {
        guard let selectedProfileId else {
            return core.selectedProfile
        }
        return core.profiles.first(where: { $0.id == selectedProfileId })
    }
}

struct ProfileEditorSection: View {
    @State var profile: ProfileConfig
    let templateSets: [CommandTemplateSet]
    let onSave: (ProfileConfig) -> Void
    let onSaveCredential: (String, String) -> Void

    @State private var gatewayURLText: String = ""
    @State private var credentialText: String = ""
    @State private var validationError: String?
    @State private var credentialSaved = false

    var body: some View {
        Section {
            TextField("Name", text: $profile.name)
            TextField("Gateway URL", text: $gatewayURLText)
                .onChange(of: gatewayURLText) { _, newValue in
                    if let url = URL(string: newValue), url.scheme != nil, url.host != nil {
                        profile.gatewayURL = url
                        validationError = nil
                    } else if !newValue.isEmpty {
                        validationError = "Invalid URL"
                    }
                }
            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }
            Picker("Kind", selection: $profile.kind) {
                Text("Local").tag(ProfileKind.local)
                Text("Remote").tag(ProfileKind.remote)
            }
            Picker("Auth", selection: $profile.authMode) {
                Text("None").tag(ProfileAuthMode.none)
                Text("Token").tag(ProfileAuthMode.token)
                Text("Password").tag(ProfileAuthMode.password)
            }
            .onChange(of: profile.authMode) { _, newValue in
                let normalized = newValue.normalized
                if (normalized == .token || normalized == .password) && (profile.tokenRef ?? "").isEmpty {
                    profile.tokenRef = "gateway.credential.\(profile.id.uuidString.prefix(8))"
                }
                credentialText = ""
                credentialSaved = false
            }
        } header: {
            HStack {
                Text("Gateway Connection")
                customBadge(text: profile.kind == .remote ? "Remote" : "Local")
            }
        }

        if profile.authMode.normalized == .token || profile.authMode.normalized == .password {
            Section {
                HStack {
                    SecureField(
                        profile.authMode.normalized == .password ? "Password" : "Token",
                        text: $credentialText
                    )
                    .onChange(of: credentialText) { _, _ in credentialSaved = false }
                    if credentialSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Stored in secure local storage. Keychain is used when enabled for this install.")
            }
        }

        Section {
            if profile.kind == .remote {
                TextField("SSH reference", text: Binding(
                    get: { profile.sshRef ?? "" },
                    set: { profile.sshRef = $0.isEmpty ? nil : $0 }
                ))
            }
            Picker("Template Set", selection: $profile.commandTemplateSetId) {
                ForEach(templateSets) { set in
                    Text(set.name).tag(set.id)
                }
            }
            Toggle("Enabled", isOn: $profile.enabled)
        } header: {
            Text("Options")
        }

        Section {
            HStack {
                Spacer()
                Button("Save Gateway") { saveProfile() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { gatewayURLText = profile.gatewayURL.absoluteString }
    }

    private func saveProfile() {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Profile name cannot be empty."
            return
        }
        guard URL(string: gatewayURLText)?.scheme != nil else {
            validationError = "Invalid URL. Expected format: http://host:port"
            return
        }
        validationError = nil
        let trimmedCred = credentialText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCred.isEmpty, let ref = profile.tokenRef {
            onSaveCredential(ref, trimmedCred)
            credentialSaved = true
        }
        onSave(profile)
    }
}
