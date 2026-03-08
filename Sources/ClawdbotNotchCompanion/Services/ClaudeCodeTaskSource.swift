import AppKit
import Foundation
import os.log

final class ClaudeCodeTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .claudeCode

    private static let log = Logger(subsystem: "com.clawdbot.notch", category: "ClaudeCodeTaskSource")

    private let pollInterval: TimeInterval
    private var isRunning = false
    private let localReader = ClaudeCodeLocalReader()

    init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let claudeStateDirectory = "\(home)/.claude"
        return claudeBinaryCandidates().contains { FileManager.default.fileExists(atPath: $0) }
            || FileManager.default.fileExists(atPath: claudeStateDirectory)
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        isRunning = true
        return AsyncStream { [weak self] continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                while self.isRunning && !Task.isCancelled {
                    let snapshots = await self.scanProcesses()
                    continuation.yield(snapshots)
                    try? await Task.sleep(for: .seconds(self.pollInterval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopMonitoring() async {
        isRunning = false
    }

    private func scanProcesses() async -> [ExternalTaskSnapshot] {
        let output = runCommand("/bin/ps", arguments: ["-axo", "pid=,command="])
        guard let output else {
            Self.log.warning("ps command returned nil output")
            return []
        }

        var snapshots: [ExternalTaskSnapshot] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            guard isClaudeCLIProcess(line) else { continue }

            let pid = extractPID(from: line)
            let cwd = pid.flatMap { extractCWD(pid: $0) }

            Self.log.info("Detected claude process: pid=\(pid ?? 0) cwd=\(cwd ?? "nil", privacy: .public)")

            let workspaceName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

            // Try to correlate via --resume sessionId first, then fall back to CWD-based lookup
            let resumeSessionId = extractResumeSessionId(from: line)
            let sessionInfo: ClaudeCodeLocalReader.SessionInfo?
            if let resumeSessionId, let cwd {
                sessionInfo = localReader.readSession(id: resumeSessionId, cwd: cwd)
            } else {
                sessionInfo = cwd.flatMap { localReader.readActiveSessionForCWD($0) }
            }

            Self.log.info("  session=\(sessionInfo?.sessionId ?? "none", privacy: .public) status=\(String(describing: sessionInfo?.detectedStatus), privacy: .public) title=\(sessionInfo?.title ?? "N/A", privacy: .public)")

            var metadata: [String: String] = [:]
            if let cwd { metadata["cwd"] = cwd }

            let title: String
            let progress: String?
            let status: TaskStatus

            if let info = sessionInfo {
                title = info.title
                status = info.detectedStatus
                metadata["sessionId"] = info.sessionId
                if let branch = info.gitBranch { metadata["branch"] = branch }
                if let model = info.model { metadata["model"] = model }
                if let version = info.version { metadata["version"] = version }
                if let slug = info.slug { metadata["slug"] = slug }
                if let pm = info.permissionMode { metadata["permissionMode"] = pm }

                // Build a richer progress string
                var progressParts: [String] = []
                if let model = info.model {
                    // Shorten model name: "claude-opus-4-6" -> "opus-4-6"
                    let shortModel = model.replacingOccurrences(of: "claude-", with: "")
                    progressParts.append(shortModel)
                }
                if let branch = info.gitBranch {
                    progressParts.append(branch)
                }
                progress = progressParts.isEmpty ? "Working..." : progressParts.joined(separator: " · ")
            } else {
                title = "Claude Code session"
                status = .running
                progress = "Working..."
            }

            let snapshot = ExternalTaskSnapshot(
                id: "claude-\(pid ?? 0)",
                sourceKind: .claudeCode,
                title: title,
                workspace: workspaceName,
                status: status,
                progress: progress,
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: sessionInfo?.lastTimestamp ?? Date(),
                deepLinkURL: nil,
                metadata: metadata
            )
            snapshots.append(snapshot)
        }

        Self.log.info("ClaudeCode scan complete: \(snapshots.count) snapshots")
        return snapshots
    }

    /// Check if a ps output line represents a Claude CLI process.
    /// Uses broad string matching to handle paths with spaces (e.g. "Application Support/...").
    /// Filters out Claude Desktop (Electron), shell-snapshots, crashpad, and helper processes.
    private func isClaudeCLIProcess(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Split into PID and the rest (command + args)
        let components = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2 else { return false }
        let commandLine = String(components[1])

        // Skip non-claude processes early
        guard commandLine.contains("claude") else { return false }

        // Exclude Desktop app (Electron), helpers, crashpad, shell-snapshots, grep
        let exclusions = ["Claude.app", "Claude Helper", "claude_crashpad", "shell-snapshots", "grep"]
        for exclusion in exclusions {
            if commandLine.contains(exclusion) { return false }
        }

        // Match: /claude in a path, " claude " with args, bare "claude", or "claude " at start
        return commandLine.contains("/claude")
            || commandLine.contains(" claude ")
            || commandLine == "claude"
            || commandLine.hasPrefix("claude ")
    }

    /// Extract --resume <sessionId> from command line args for direct JSONL correlation.
    private func extractResumeSessionId(from line: String) -> String? {
        guard let range = line.range(of: "--resume ") else { return nil }
        let remainder = line[range.upperBound...]
        let token = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        return token.map(String.init)
    }

    private func extractPID(from psLine: String) -> Int? {
        let components = psLine.split(separator: " ", omittingEmptySubsequences: true)
        guard let pidComponent = components.first else { return nil }
        return Int(pidComponent)
    }

    private func extractCWD(pid: Int) -> String? {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-a", "-p", "\(pid)", "-Fn", "-d", "cwd"])
        guard let output else { return nil }
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") && line.count > 1 {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    private func claudeBinaryCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
    }

    private func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
