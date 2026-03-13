import XCTest
@testable import AICP

final class ClaudeCodeTaskSourceProcessDetectionTests: XCTestCase {
    func testStandaloneClaudeCLIProcessIsTracked() {
        let line = "12345 /opt/homebrew/bin/claude --resume abc123"

        XCTAssertTrue(ClaudeCodeTaskSource.isTrackableClaudeCLIProcess(line))
    }

    func testClaudeDesktopDisclaimerWrapperIsIgnored() {
        let line = "12345 /Applications/Claude.app/Contents/Helpers/disclaimer /Users/apupneja/Library/Application Support/Claude/claude-code/2.1.64/claude --output-format stream-json"

        XCTAssertFalse(ClaudeCodeTaskSource.isTrackableClaudeCLIProcess(line))
    }

    func testClaudeDesktopLocalAgentWorkerIsIgnored() {
        let line = "12345 /Users/apupneja/Library/Application Support/Claude/claude-code/2.1.64/claude --plugin-dir /Users/apupneja/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/example"

        XCTAssertFalse(ClaudeCodeTaskSource.isTrackableClaudeCLIProcess(line))
    }
}
