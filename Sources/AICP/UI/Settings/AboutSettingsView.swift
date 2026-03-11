import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var updateManager: UpdateManager
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showBuildNumber = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    appIcon
                        .frame(width: 64, height: 64)

                    Text("AICP")
                        .font(.title3.weight(.bold))

                    Text("AI Control Plane")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section("Version") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture { showBuildNumber.toggle() }

                if showBuildNumber, let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(build)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Support") {
                Button {
                    if let url = URL(string: "mailto:anirudh.pupneja@redapto.com?subject=AICP%20Bug%20Report") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }

                Button {
                    if let url = URL(string: "mailto:anirudh.pupneja@redapto.com?subject=AICP%20Feedback") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }

            Section("Diagnostics") {
                HStack {
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
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Updates") {
                Button {
                    updateManager.checkForUpdates()
                } label: {
                    Label("Check for Updates\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!updateManager.canCheckForUpdates)
                .help(updateManager.canCheckForUpdates ? "Check for updates" : "No update feed configured.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    private var appIcon: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else if let image = Bundle.main.image(forResource: NSImage.Name("AppIcon")) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .aspectRatio(contentMode: .fit)
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
