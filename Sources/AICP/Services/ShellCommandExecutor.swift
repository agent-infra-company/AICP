import Foundation

struct CommandExecutionResult: Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol ShellCommandExecuting: AnyObject, Sendable {
    func execute(command: String) async throws -> CommandExecutionResult
}

final class ShellCommandExecutor: ShellCommandExecuting,  Sendable {
    /// Common tool directories that may not be in PATH when launched from Finder/Spotlight.
    private static let extraPathDirs = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "~/bin",
        "~/.local/bin",
        "~/.cargo/bin",
        "~/.bun/bin",
        "~/Library/pnpm",
        "~/.npm-global/bin",
        "~/.asdf/shims",
    ]

    func execute(command: String) async throws -> CommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")

                // Ensure common tool paths are available even when launched
                // from Finder/Spotlight where PATH is minimal.
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = Self.augmentedPATH(environment: env)
                process.environment = env
                process.arguments = ["-lc", Self.resolvedCommand(command, environment: env)]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    let stdoutDrainer = PipeDrainer(handle: stdoutPipe.fileHandleForReading, label: "aicp.shell.stdout")
                    let stderrDrainer = PipeDrainer(handle: stderrPipe.fileHandleForReading, label: "aicp.shell.stderr")

                    process.waitUntilExit()

                    let stdoutData = stdoutDrainer.waitForData()
                    let stderrData = stderrDrainer.waitForData()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    continuation.resume(returning: CommandExecutionResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func resolvedCommand(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        launchAgentSearchPaths: [URL]? = nil,
        executableSearchPaths: [String]? = nil
    ) -> String {
        guard command.hasPrefix("openclaw ") || command == "openclaw" else {
            return command
        }
        guard let executablePath = resolveOpenClawExecutable(
            environment: environment,
            launchAgentSearchPaths: launchAgentSearchPaths,
            executableSearchPaths: executableSearchPaths
        ) else {
            return command
        }

        if command == "openclaw" {
            return executablePath
        }
        return executablePath + command.dropFirst("openclaw".count)
    }

    static func resolveOpenClawExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        launchAgentSearchPaths: [URL]? = nil,
        executableSearchPaths: [String]? = nil
    ) -> String? {
        if let explicitPath = normalizedExecutablePath(environment["OPENCLAW_BIN"]) {
            return explicitPath
        }

        for plistURL in launchAgentSearchPaths ?? defaultOpenClawLaunchAgentPaths() {
            guard
                let data = try? Data(contentsOf: plistURL),
                let path = openClawPath(fromLaunchAgentPlistData: data)
            else {
                continue
            }
            return path
        }

        let searchPaths = executableSearchPaths ?? self.executableSearchPaths(environment: environment)
        if let discoveredPath = findExecutable(named: "openclaw", searchPaths: searchPaths) {
            return discoveredPath
        }

        return nil
    }

    private static func augmentedPATH(environment: [String: String]) -> String {
        executableSearchPaths(environment: environment).joined(separator: ":")
    }

    private static func executableSearchPaths(environment: [String: String]) -> [String] {
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let configuredPaths = currentPath
            .split(separator: ":")
            .map(String.init)
        let extraPaths = extraPathDirs.map { ($0 as NSString).expandingTildeInPath }
        return deduplicatedPaths(extraPaths + configuredPaths)
    }

    private static func deduplicatedPaths(_ paths: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        for rawPath in paths {
            let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { continue }

            let normalizedPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
            if seen.insert(normalizedPath).inserted {
                result.append(normalizedPath)
            }
        }

        return result
    }

    private static func findExecutable(named name: String, searchPaths: [String]) -> String? {
        for directory in searchPaths {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func normalizedExecutablePath(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            return nil
        }
        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    private static func defaultOpenClawLaunchAgentPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Library/LaunchAgents/ai.openclaw.gateway.plist",
            "/Library/LaunchAgents/ai.openclaw.gateway.plist",
        ]

        return deduplicatedPaths(candidates).map(URL.init(fileURLWithPath:))
    }

    private static func openClawPath(fromLaunchAgentPlistData data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let root = plist as? [String: Any],
            let args = root["ProgramArguments"] as? [String],
            let firstArg = args.first
        else {
            return nil
        }

        let lastPathComponent = URL(fileURLWithPath: firstArg).lastPathComponent
        guard lastPathComponent == "openclaw" else {
            return nil
        }

        return normalizedExecutablePath(firstArg)
    }
}

private final class PipeDrainer: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var data = Data()

    init(handle: FileHandle, label: String) {
        DispatchQueue(label: label).async { [weak self] in
            guard let self else { return }
            self.data = handle.readDataToEndOfFile()
            self.semaphore.signal()
        }
    }

    func waitForData() -> Data {
        semaphore.wait()
        return data
    }
}
