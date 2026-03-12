import AppKit
import SwiftUI

enum OnboardingAssetLoader {
    static func appIcon() -> NSImage? {
        for bundle in [Bundle.appModule, Bundle.main] {
            if let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }

            if let image = bundle.image(forResource: NSImage.Name("AppIcon")) {
                return image
            }
        }

        return nil
    }
}

// MARK: - Welcome

struct OnboardingWelcomeStep: View {
    private let appIcon = OnboardingAssetLoader.appIcon()

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "capsule.tophalf.filled")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 80, height: 80)

            Text("Welcome to AICP")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Your macOS notch control plane for\nAI task coordination.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 8) {
                featurePill(icon: "rectangle.topthird.inset.filled", label: "Notch UI")
                featurePill(icon: "text.bubble", label: "Task Control")
                featurePill(icon: "bell.badge", label: "Notifications")
            }
            .padding(.top, 4)
        }
    }

    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
    }
}

// MARK: - Gateway (Optional OpenClaw Setup)

struct OnboardingGatewayStep: View {
    let onEnable: () async -> Void
    let onSkip: () -> Void

    @State private var enabling = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("OpenClaw Gateway")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Connect to a local OpenClaw gateway for task routing and agent coordination.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Text("If you skip this, you can still use Claude Code, Codex, and other CLIs directly.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            VStack(spacing: 10) {
                Button {
                    enabling = true
                    Task {
                        await onEnable()
                        enabling = false
                    }
                } label: {
                    HStack {
                        if enabling {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text("Enable")
                    }
                    .frame(width: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(enabling)

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 13))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Reusable Permission Step (boring.notch pattern)

struct OnboardingPermissionStep: View {
    let icon: String
    let title: String
    let description: String
    var privacyNote: String?
    var allowLabel: String = "Allow"
    var skipLabel: String = "Skip"
    let onAllow: () async -> Void
    let onSkip: () -> Void

    @State private var requesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if let privacyNote {
                Text(privacyNote)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            VStack(spacing: 10) {
                Button {
                    requesting = true
                    Task {
                        await onAllow()
                        requesting = false
                    }
                } label: {
                    HStack {
                        if requesting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(allowLabel)
                    }
                    .frame(width: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(requesting)

                Button(skipLabel) {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
                .font(.system(size: 13))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Completion

struct OnboardingCompletionStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                tipRow(icon: "rectangle.topthird.inset.filled", text: "Hover the notch to expand AICP")
                tipRow(icon: "text.bubble", text: "Type a prompt to send tasks")
                tipRow(icon: "bell", text: "Get notified when tasks need attention")
                tipRow(icon: "gearshape", text: "Adjust gateways later in Settings")
            }
            .frame(maxWidth: 320)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
