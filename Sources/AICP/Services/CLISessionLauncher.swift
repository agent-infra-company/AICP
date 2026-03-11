import AppKit
import Foundation
import os.log

enum CLISessionEvent: Sendable {
    case launched
    case failed(error: String)
}

/// Launches CLI sessions in a visible Terminal.app window.
/// The session is then picked up by the existing task source polling
/// (ClaudeCodeTaskSource / CodexTaskSource) for status tracking.
actor CLISessionLauncher {
    private static let log = ControlPlaneDiagnostics.logger(category: "CLISessionLauncher")

    /// Launch a CLI session in a new Terminal.app window (background).
    func launch(cli: TaskSourceKind, prompt: String, cwd: String) async throws {
        let binaryPath = try resolveBinary(for: cli)

        Self.log.info(
            "Launching terminal session cli=\(cli.rawValue, privacy: .public) cwd=\(cwd, privacy: .public)"
        )

        try launchViaShellScript(binary: binaryPath, prompt: prompt, cwd: cwd)
    }

    // MARK: - Terminal Launcher

    /// Writes a temporary .command script that `exec`s the CLI interactively,
    /// then opens it in the background via `open -g`.
    private func launchViaShellScript(binary: String, prompt: String, cwd: String) throws {
        // Use `exec` so the CLI replaces the shell — the terminal stays open
        // as long as the interactive session is running.
        // When a prompt is provided, pass it directly to the CLI so the agent
        // starts working immediately without the user needing to paste.
        let execLine: String
        if prompt.isEmpty {
            execLine = "exec \(bashQuote(binary))"
        } else {
            execLine = "exec \(bashQuote(binary)) \(bashQuote(prompt))"
        }

        let scriptContent = """
            #!/bin/bash
            clear
            cd \(bashQuote(cwd))
            \(execLine)
            """

        let tempDir = FileManager.default.temporaryDirectory
        let scriptName = "clawy-session-\(UUID().uuidString).command"
        let scriptURL = tempDir.appendingPathComponent(scriptName)

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        Self.log.info("Opening terminal script at \(scriptURL.path, privacy: .public)")

        // -g opens in background without stealing focus
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CLILaunchError.scriptFailed("open command exited with status \(process.terminationStatus)")
        }

        // Clean up the temp script after a short delay to allow Terminal to read it.
        Task {
            try? await Task.sleep(for: .seconds(5))
            try? FileManager.default.removeItem(at: scriptURL)
            Self.log.debug("Cleaned up temp script \(scriptURL.lastPathComponent, privacy: .public)")
        }
    }

    /// Single-quote a string for bash, handling embedded single quotes.
    private func bashQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    // MARK: - Binary Resolution

    private func resolveBinary(for cli: TaskSourceKind) throws -> String {
        let candidates: [String]
        switch cli {
        case .claudeCode:
            candidates = claudeCodeBinaryCandidates()
        case .codex:
            candidates = codexBinaryCandidates()
        default:
            throw CLILaunchError.unsupportedCLI(cli.displayName)
        }

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw CLILaunchError.binaryNotFound(cli.displayName)
        }
        return path
    }

    func claudeCodeBinaryCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
    }

    func codexBinaryCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
    }

    /// Removes stale `clawy-session-*.command` temp scripts from previous runs.
    func cleanupStaleTempScripts() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        guard let contents = try? fm.contentsOfDirectory(atPath: tempDir.path) else { return }

        let staleScripts = contents.filter { $0.hasPrefix("clawy-session-") && $0.hasSuffix(".command") }
        for script in staleScripts {
            let url = tempDir.appendingPathComponent(script)
            try? fm.removeItem(at: url)
        }

        if !staleScripts.isEmpty {
            Self.log.info("Cleaned up \(staleScripts.count) stale temp scripts on startup")
        }
    }

    func isAvailable(_ cli: TaskSourceKind) -> Bool {
        switch cli {
        case .claudeCode:
            return claudeCodeBinaryCandidates().contains { FileManager.default.fileExists(atPath: $0) }
        case .codex:
            return codexBinaryCandidates().contains { FileManager.default.fileExists(atPath: $0) }
        default:
            return false
        }
    }

}

enum CLILaunchError: LocalizedError {
    case binaryNotFound(String)
    case unsupportedCLI(String)
    case directoryNotFound(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name): return "\(name) CLI not found. Make sure it's installed."
        case .unsupportedCLI(let name): return "\(name) is not supported for direct sessions."
        case .directoryNotFound(let path): return "Directory not found: \(path)"
        case .scriptFailed(let message): return "Failed to open terminal: \(message)"
        }
    }
}
