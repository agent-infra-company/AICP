import Foundation
import os.log

protocol DiagnosticsExporting: Sendable {
    func exportDiagnostics() async throws -> URL
}

actor DiagnosticsExporter: DiagnosticsExporting {
    private static let log = CompanionDiagnostics.logger(category: "DiagnosticsExporter")

    func exportDiagnostics() async throws -> URL {
        let fm = FileManager.default

        // Create a temporary staging directory
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("AICPDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // 1. Collect system info
        let info = buildSystemInfo()
        let infoData = try JSONSerialization.data(
            withJSONObject: info,
            options: [.prettyPrinted, .sortedKeys]
        )
        try infoData.write(to: stagingDir.appendingPathComponent("diagnostics-info.json"))

        // 2. Copy telemetry log(s) if they exist
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let telemetryDir = appSupport.appendingPathComponent("AICP", isDirectory: true)
        let telemetryLog = telemetryDir.appendingPathComponent("telemetry.log")
        let telemetryRotated = telemetryDir.appendingPathComponent("telemetry.log.1")

        if fm.fileExists(atPath: telemetryLog.path) {
            try? fm.copyItem(
                at: telemetryLog,
                to: stagingDir.appendingPathComponent("telemetry.log")
            )
        }
        if fm.fileExists(atPath: telemetryRotated.path) {
            try? fm.copyItem(
                at: telemetryRotated,
                to: stagingDir.appendingPathComponent("telemetry.log.1")
            )
        }

        // 3. Create zip using ditto
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let dateString = dateFormatter.string(from: Date())
        let zipURL = fm.temporaryDirectory
            .appendingPathComponent("AICPDiagnostics-\(dateString).zip")

        // Remove any existing zip at the same path
        try? fm.removeItem(at: zipURL)

        let logger = Self.log
        guard let _ = ProcessProbe.run(
            path: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", stagingDir.path, zipURL.path],
            logger: logger,
            label: "ditto-zip"
        ) else {
            throw DiagnosticsError.zipFailed
        }

        // Clean up staging directory
        try? fm.removeItem(at: stagingDir)

        Self.log.info("Diagnostics exported to \(zipURL.path, privacy: .public)")
        return zipURL
    }

    private func buildSystemInfo() -> [String: String] {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion

        return [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "osVersion": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "isBundledApp": String(AppRuntimeEnvironment.current.isBundledApp),
            "exportDate": ISO8601DateFormatter().string(from: Date()),
        ]
    }
}

enum DiagnosticsError: LocalizedError {
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .zipFailed:
            return "Failed to create diagnostics archive."
        }
    }
}
