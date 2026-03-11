import XCTest
@testable import AICP

final class ExternalSnapshotActivityDetectorTests: XCTestCase {
    func testNewNonCursorSnapshotAlwaysAnnounces() {
        let snapshot = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(),
            metadata: ["source": "cli"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    // MARK: - Cursor-specific tests

    func testNewCursorChatOnlyDoesNotAnnounce() {
        let snapshot = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(),
            metadata: ["roles": "user"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    func testNewCursorAgentSessionAnnounces() {
        let snapshot = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(),
            metadata: ["roles": "agent-exec,user"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    func testCursorAgentStartsAnnounces() {
        let old = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["roles": "user"]
        )
        let new = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 105),
            metadata: ["roles": "agent-exec,user"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCursorAgentCompletesAnnounces() {
        let old = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["roles": "agent-exec,user"]
        )
        let new = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 105),
            metadata: ["roles": "user"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCursorSameRolesDoNotAnnounce() {
        let old = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["roles": "user"]
        )
        let new = makeSnapshot(
            id: "my-project",
            sourceKind: .cursor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 105),
            metadata: ["roles": "user"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    // MARK: - Conductor-specific tests

    func testNewConductorIdleSessionDoesNotAnnounce() {
        let snapshot = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .completed,
            updatedAt: Date(),
            metadata: [:]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    func testNewConductorWorkingSessionAnnounces() {
        let snapshot = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .running,
            updatedAt: Date(),
            metadata: [:]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    func testConductorStatusChangeAnnounces() {
        let old = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: [:]
        )
        let new = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 105),
            metadata: [:]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testConductorSameStatusDoesNotAnnounce() {
        let old = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: [:]
        )
        let new = makeSnapshot(
            id: "session-1",
            sourceKind: .conductor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 105),
            metadata: [:]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    // MARK: - General tests

    func testNeedsInputTurnAdvancementAnnounces() {
        let old = makeSnapshot(
            id: "claude-thread",
            sourceKind: .claudeCode,
            status: .needsInput,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: [:]
        )
        let new = makeSnapshot(
            id: "claude-thread",
            sourceKind: .claudeCode,
            status: .needsInput,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: [:]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLIFollowUpTurnAnnouncesWhileStillRunning() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli", "turnId": "turn-2"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLISameTurnRunningUpdatesDoNotAnnounce() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLIFallsBackToUpdatedAtWhenTurnIdentifiersAreMissing() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testNonCLIRepeatedRunningUpdatesDoNotAnnounce() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "vscode"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "vscode"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    private func makeSnapshot(
        id: String,
        sourceKind: TaskSourceKind,
        status: TaskStatus,
        updatedAt: Date,
        metadata: [String: String]
    ) -> ExternalTaskSnapshot {
        ExternalTaskSnapshot(
            id: id,
            sourceKind: sourceKind,
            title: "Task",
            workspace: nil,
            status: status,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: updatedAt,
            deepLinkURL: nil,
            metadata: metadata
        )
    }
}
