import XCTest
@testable import AICP

final class CursorProcessSnapshotParserTests: XCTestCase {
    func testParseExtractsWorkspaceAndRole() {
        let parser = CursorProcessSnapshotParser()
        let line = "Cursor Helper (Plugin): extension-host (agent-exec) signal-arena [1-3]"

        let activity = parser.parse(line: line)

        XCTAssertEqual(activity?.workspace, "signal-arena")
        XCTAssertEqual(activity?.role, .agentExec)
    }

    func testParseIgnoresUnrelatedProcesses() {
        let parser = CursorProcessSnapshotParser()
        let line = "Cursor Helper: shared-process"

        XCTAssertNil(parser.parse(line: line))
    }

    func testProgressTextUsesStableOrdering() {
        let parser = CursorProcessSnapshotParser()
        let text = parser.progressText(for: [.user, .retrieval, .agentExec])

        XCTAssertEqual(text, "Agent · Retrieval · Chat")
    }
}
