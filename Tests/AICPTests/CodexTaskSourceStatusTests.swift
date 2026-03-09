import XCTest
@testable import AICP

final class CodexTaskSourceStatusTests: XCTestCase {
    func testCLIThreadRequiresLiveCLIWorkspaceToStayRunning() {
        let updatedDate = Date(timeIntervalSince1970: 100)

        let completed = CodexTaskSource.statusForThread(
            source: "cli",
            cwd: "/Users/apupneja/Projects",
            rolloutPath: nil,
            runningWorkspaces: [],
            isDesktopAppRunning: true,
            updatedDate: updatedDate,
            now: Date(timeIntervalSince1970: 110)
        )

        let running = CodexTaskSource.statusForThread(
            source: "cli",
            cwd: "/Users/apupneja/Projects",
            rolloutPath: nil,
            runningWorkspaces: ["/Users/apupneja/Projects"],
            isDesktopAppRunning: false,
            updatedDate: updatedDate,
            now: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(completed, .completed)
        XCTAssertEqual(running, .running)
    }

    func testRecentDesktopThreadCanStayRunningWhileAppIsOpen() {
        let status = CodexTaskSource.statusForThread(
            source: "vscode",
            cwd: "/Users/apupneja/Projects/clawy",
            rolloutPath: nil,
            runningWorkspaces: [],
            isDesktopAppRunning: true,
            updatedDate: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(status, .running)
    }

    func testCLIRolloutTaskCompleteMarksThreadCompleted() throws {
        let rolloutPath = try makeRolloutFile(lines: [
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
        ])

        let status = CodexTaskSource.statusForThread(
            source: "cli",
            cwd: "/Users/apupneja/Projects",
            rolloutPath: rolloutPath,
            runningWorkspaces: ["/Users/apupneja/Projects"],
            isDesktopAppRunning: false,
            updatedDate: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(status, .completed)
    }

    func testCLIRolloutTaskStartedKeepsThreadRunning() throws {
        let rolloutPath = try makeRolloutFile(lines: [
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        ])

        let status = CodexTaskSource.statusForThread(
            source: "cli",
            cwd: "/Users/apupneja/Projects",
            rolloutPath: rolloutPath,
            runningWorkspaces: [],
            isDesktopAppRunning: false,
            updatedDate: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(status, .running)
    }

    func testCLIRolloutTurnAbortedMarksThreadCanceled() throws {
        let rolloutPath = try makeRolloutFile(lines: [
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1"}}"#,
        ])

        let status = CodexTaskSource.statusForThread(
            source: "cli",
            cwd: "/Users/apupneja/Projects",
            rolloutPath: rolloutPath,
            runningWorkspaces: ["/Users/apupneja/Projects"],
            isDesktopAppRunning: false,
            updatedDate: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(status, .canceled)
    }

    func testCLIRolloutStateIncludesTurnIdentifier() throws {
        let rolloutPath = try makeRolloutFile(lines: [
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-42"}}"#,
        ])

        let rolloutState = CodexTaskSource.cliRolloutState(atPath: rolloutPath)

        XCTAssertEqual(rolloutState?.status, .running)
        XCTAssertEqual(rolloutState?.turnId, "turn-42")
    }

    private func makeRolloutFile(lines: [String]) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("rollout.jsonl")
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }
}
