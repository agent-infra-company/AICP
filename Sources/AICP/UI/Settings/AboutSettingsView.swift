import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("About")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(spacing: 20) {
                    Image(systemName: "capsule.tophalf.filled")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)

                    Text("AICP - AI Control Plane")
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

            GroupBox("Feedback") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Help improve AICP by reporting bugs or suggesting features.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            // TODO: Replace with actual GitHub Issues URL
                            if let url = URL(string: "https://github.com/your-org/aicp/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Report an Issue", systemImage: "exclamationmark.bubble")
                        }

                        Button {
                            if let url = URL(string: "mailto:support@aicp.dev?subject=AICP%20Feedback") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Email Support", systemImage: "envelope")
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export telemetry log and system info for troubleshooting.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            exportDiagnostics()
                        } label: {
                            Label("Export Diagnostics\u{2026}", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isExporting)

                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let exportError {
                        Text(exportError)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }

            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        // Placeholder — will be wired to Sparkle
                    } label: {
                        Label("Check for Updates\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(true)
                    .help("Auto-updates coming soon")
                }
                .padding(8)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func exportDiagnostics() {
        isExporting = true
        exportError = nil

        Task {
            do {
                let exporter = DiagnosticsExporter()
                let zipURL = try await exporter.exportDiagnostics()

                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.nameFieldStringValue = zipURL.lastPathComponent
                    savePanel.allowedContentTypes = [.zip]
                    savePanel.canCreateDirectories = true

                    if savePanel.runModal() == .OK, let destination = savePanel.url {
                        try? FileManager.default.copyItem(at: zipURL, to: destination)
                    }

                    // Clean up the temp zip
                    try? FileManager.default.removeItem(at: zipURL)
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}
