import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "capsule.tophalf.filled")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Welcome to AICP")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your macOS notch companion for AI task coordination.\nMonitor tasks, send prompts, and stay in control — all from your menu bar.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .lineSpacing(4)

            HStack(spacing: 10) {
                featurePill(icon: "rectangle.topthird.inset.filled", label: "Notch Companion")
                featurePill(icon: "text.bubble", label: "AI Task Control")
                featurePill(icon: "bell.badge", label: "Smart Notifications")
                featurePill(icon: "terminal", label: "CLI Integration")
            }
            .padding(.top, 4)
        }
    }

    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
    }
}

struct OnboardingNotificationStep: View {
    @ObservedObject var core: CompanionCore
    @State private var granted = false
    @State private var requested = false
    private let environment = AppRuntimeEnvironment.current

    private var canRequestNotifications: Bool { environment.supportsNotifications }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Stay in the Loop")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Get notified when tasks complete, fail, or need your input.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if granted {
                Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if !canRequestNotifications {
                Text("Notification permissions are unavailable in `swift run` mode. Launch the app bundle to enable them.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            } else if !requested {
                Button("Allow Notifications") {
                    Task {
                        guard canRequestNotifications else { return }
                        granted = await core.requestNotificationAuthorization()
                        requested = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            } else {
                Text("You can enable notifications later in System Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .animation(.spring(response: 0.35), value: granted)
        .animation(.spring(response: 0.35), value: requested)
    }
}

struct OnboardingProfileStep: View {
    @ObservedObject var core: CompanionCore
    @State private var profileName = "Local OpenClaw"
    @State private var gatewayURL = "http://127.0.0.1:4689"
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("Connect to OpenClaw")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Configure your local OpenClaw gateway connection.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Profile Name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Gateway URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Gateway URL", text: $gatewayURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: gatewayURL) { _, newValue in
                            if let url = URL(string: newValue), url.scheme != nil, url.host != nil {
                                validationError = nil
                            } else if !newValue.isEmpty {
                                validationError = "Enter a valid URL (e.g. http://127.0.0.1:4689)"
                            }
                        }
                }

                if let validationError {
                    Text(validationError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 400)
        }
        .onAppear {
            if let existing = core.profiles.first {
                profileName = existing.name
                gatewayURL = existing.gatewayURL.absoluteString
            }
        }
        .onDisappear {
            saveProfile()
        }
    }

    private func saveProfile() {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Profile name cannot be empty."
            return
        }
        guard let url = URL(string: gatewayURL), url.scheme != nil, url.host != nil else {
            validationError = "Enter a valid URL (e.g. http://127.0.0.1:4689)"
            return
        }
        if var existing = core.profiles.first {
            existing.name = trimmedName
            existing.gatewayURL = url
            core.upsertProfile(existing)
        } else {
            guard let templateId = core.commandTemplateSets.first?.id else { return }
            let profile = ProfileConfig(
                id: UUID(), name: trimmedName, kind: .local,
                gatewayURL: url, authMode: .none, tokenRef: nil,
                sshRef: nil, commandTemplateSetId: templateId, enabled: true
            )
            core.upsertProfile(profile)
        }
    }
}

struct OnboardingCompletionStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                tipRow(icon: "rectangle.topthird.inset.filled", text: "Hover over the notch to expand AICP")
                tipRow(icon: "text.bubble", text: "Type a prompt to send tasks to OpenClaw")
                tipRow(icon: "bell", text: "You'll be notified when tasks need attention")
                tipRow(icon: "gearshape", text: "Access settings from the menu bar icon")
            }
            .frame(maxWidth: 380)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
