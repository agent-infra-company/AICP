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
    func execute(command: String) async throws -> CommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]

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
