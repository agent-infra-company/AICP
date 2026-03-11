import XCTest
@testable import AICP

final class ShellCommandExecutorTests: XCTestCase {
    func testExecuteDrainsLargeStdoutWithoutDeadlocking() async throws {
        let executor = ShellCommandExecutor()
        let finished = expectation(description: "shell command executor returns")

        final class Box: @unchecked Sendable {
            var result: CommandExecutionResult?
            var error: Error?
        }

        let box = Box()

        Task.detached {
            do {
                box.result = try await executor.execute(command: "/usr/bin/jot 40000")
            } catch {
                box.error = error
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 2.0)
        XCTAssertNil(box.error)
        XCTAssertEqual(box.result?.exitCode, 0)
        XCTAssertTrue(box.result?.stdout.hasPrefix("1\n2\n3\n") == true)
    }

    func testResolvedCommandUsesAbsolutePathFromEnvironmentOverride() throws {
        let executableURL = try makeExecutable(named: "openclaw")
        defer { try? FileManager.default.removeItem(at: executableURL.deletingLastPathComponent()) }

        let resolved = ShellCommandExecutor.resolvedCommand(
            "openclaw gateway status",
            environment: ["OPENCLAW_BIN": executableURL.path]
        )

        XCTAssertEqual(resolved, "\(executableURL.path) gateway status")
    }

    func testResolvedCommandFallsBackToLaunchAgentExecutablePath() throws {
        let executableURL = try makeExecutable(named: "openclaw")
        let plistURL = executableURL.deletingLastPathComponent().appendingPathComponent("ai.openclaw.gateway.plist")
        defer { try? FileManager.default.removeItem(at: executableURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "ProgramArguments": [
                executableURL.path,
                "gateway",
                "start",
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        let resolved = ShellCommandExecutor.resolvedCommand(
            "openclaw gateway start --port 4689",
            environment: ["PATH": "/usr/bin:/bin"],
            launchAgentSearchPaths: [plistURL],
            executableSearchPaths: []
        )

        XCTAssertEqual(resolved, "\(executableURL.path) gateway start --port 4689")
    }

    func testResolvedCommandLeavesCommandUntouchedWhenExecutableCannotBeFound() {
        let command = "openclaw gateway status"

        let resolved = ShellCommandExecutor.resolvedCommand(
            command,
            environment: ["PATH": "/usr/bin:/bin"],
            launchAgentSearchPaths: [],
            executableSearchPaths: []
        )

        XCTAssertEqual(resolved, command)
    }

    private func makeExecutable(named name: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let executableURL = directoryURL.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )

        return executableURL
    }
}
