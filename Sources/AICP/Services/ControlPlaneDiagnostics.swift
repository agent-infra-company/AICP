import Foundation
import os.log

enum ControlPlaneDiagnostics {
    static let subsystem = "com.aicp.app"

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static func joined<S: Sequence>(_ values: S) -> String where S.Element == String {
        let array = Array(values)
        return array.isEmpty ? "none" : array.joined(separator: ", ")
    }
}

enum ProcessProbe {
    static func run(path: String, arguments: [String], logger: Logger, label: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error(
                "\(label, privacy: .public) launch failed path=\(path, privacy: .public) arguments=\(ControlPlaneDiagnostics.joined(arguments), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        // Drain stdout/stderr concurrently before waiting so chatty commands like `ps`
        // cannot block on a full pipe and deadlock the caller.
        let stdoutDrainer = PipeDrainer(
            handle: stdoutPipe.fileHandleForReading,
            label: "aicp.processprobe.stdout"
        )
        let stderrDrainer = PipeDrainer(
            handle: stderrPipe.fileHandleForReading,
            label: "aicp.processprobe.stderr"
        )

        process.waitUntilExit()

        let stdoutData = stdoutDrainer.waitForData()
        let stderrData = stderrDrainer.waitForData()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            logger.error(
                "\(label, privacy: .public) failed status=\(process.terminationStatus) path=\(path, privacy: .public) arguments=\(ControlPlaneDiagnostics.joined(arguments), privacy: .public) stderr=\(stderr, privacy: .public)"
            )
            return nil
        }

        guard let output = String(data: stdoutData, encoding: .utf8) else {
            logger.error(
                "\(label, privacy: .public) produced non-UTF8 stdout path=\(path, privacy: .public) arguments=\(ControlPlaneDiagnostics.joined(arguments), privacy: .public)"
            )
            return nil
        }

        if !stderr.isEmpty {
            logger.debug(
                "\(label, privacy: .public) emitted stderr path=\(path, privacy: .public) stderr=\(stderr, privacy: .public)"
            )
        }

        return output
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
}
