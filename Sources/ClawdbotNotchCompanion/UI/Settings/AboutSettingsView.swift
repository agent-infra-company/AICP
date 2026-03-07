import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("About")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(spacing: 20) {
                    Image(systemName: "capsule.tophalf.filled")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)

                    Text("Clawdbot Notch Companion")
                        .font(.title3.weight(.semibold))

                    Text("Version \(appVersion)")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("A macOS notch companion for OpenClaw-powered\nAI task coordination.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}
