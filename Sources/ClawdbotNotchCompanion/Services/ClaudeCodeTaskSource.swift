import AppKit
import Foundation

final class ClaudeCodeTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .claudeCode

    private let pollInterval: TimeInterval
    private var isRunning = false

    init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: claudeBinaryPath())
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
        let output = runCommand("/bin/ps", arguments: ["aux"])
        guard let output else { return [] }

        var snapshots: [ExternalTaskSnapshot] = []
        let lines = output.components(separatedBy: "\n")

        for line in lines {
            guard line.contains("/claude") || line.contains(" claude ") else { continue }
            // Skip grep and this process
            guard !line.contains("grep") else { continue }
            // Skip Conductor-spawned instances
            guard !line.contains("\"conductor\"") && !line.contains("conductor") || !line.contains("--mcp-config") else { continue }
            // Must be a standalone Claude Code session (running in a terminal)
            guard !line.contains("--mcp-config") else { continue }

            let pid = extractPID(from: line)
            let cwd = pid.flatMap { extractCWD(pid: $0) }
            let workspaceName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

            let snapshot = ExternalTaskSnapshot(
                id: "claude-\(pid ?? 0)",
                sourceKind: .claudeCode,
                title: "Claude Code session",
                workspace: workspaceName,
                status: .running,
                progress: "Working...",
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: Date(),
                deepLinkURL: nil,
                metadata: cwd.map { ["cwd": $0] } ?? [:]
            )
            snapshots.append(snapshot)
        }

        return snapshots
    }

    private func extractPID(from psLine: String) -> Int? {
        let components = psLine.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return nil }
        return Int(components[1])
    }

    private func extractCWD(pid: Int) -> String? {
        let output = runCommand("/usr/sbin/lsof", arguments: ["-p", "\(pid)", "-Fn", "-d", "cwd"])
        guard let output else { return nil }
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("n") && line.count > 1 {
                return String(line.dropFirst())
            }
        }
        return nil
    }

    private func claudeBinaryPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin/claude"
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
