import XCTest
@testable import ClawdbotNotchCompanion

final class TaskSourceKindActivationTests: XCTestCase {
    func testConductorActivationTargetsMatchInstalledApp() {
        XCTAssertEqual(TaskSourceKind.conductor.activationBundleIdentifiers, ["com.conductor.app"])
        XCTAssertEqual(TaskSourceKind.conductor.activationApplicationPaths, ["/Applications/Conductor.app"])
    }

    func testCodexActivationTargetsPreferForegroundingApp() {
        XCTAssertEqual(TaskSourceKind.codex.activationBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(TaskSourceKind.codex.activationApplicationPaths, ["/Applications/Codex.app"])
    }

    func testCodexCLIExternalTasksPreferTerminalActivation() {
        let snapshot = ExternalTaskSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            title: "CLI task",
            workspace: "Projects",
            status: .running,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: Date(),
            deepLinkURL: nil,
            metadata: ["source": "cli"]
        )

        let task = DisplayTask(from: snapshot)

        XCTAssertEqual(
            task.activationBundleIdentifiers,
            ["com.apple.Terminal", "com.googlecode.iterm2"]
        )
        XCTAssertEqual(
            task.activationApplicationPaths,
            ["/System/Applications/Utilities/Terminal.app", "/Applications/iTerm.app"]
        )
    }

    func testCodexAppTasksKeepCodexActivationTargets() {
        let snapshot = ExternalTaskSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            title: "App task",
            workspace: "Projects",
            status: .running,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: Date(),
            deepLinkURL: nil,
            metadata: ["source": "vscode"]
        )

        let task = DisplayTask(from: snapshot)

        XCTAssertEqual(task.activationBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(task.activationApplicationPaths, ["/Applications/Codex.app"])
    }

    func testClaudeDesktopActivationTargetsMatchDesktopApp() {
        XCTAssertEqual(TaskSourceKind.claudeDesktop.activationBundleIdentifiers, ["com.anthropic.claudefordesktop"])
        XCTAssertEqual(TaskSourceKind.claudeDesktop.activationApplicationPaths, ["/Applications/Claude.app"])
    }

    func testCursorActivationTargetsMatchInstalledApp() {
        XCTAssertEqual(TaskSourceKind.cursor.activationBundleIdentifiers, ["com.todesktop.230313mzl4w4u92"])
        XCTAssertEqual(TaskSourceKind.cursor.activationApplicationPaths, ["/Applications/Cursor.app"])
    }

    func testClaudeCodeActivationTargetsSupportTerminalFallbacks() {
        XCTAssertEqual(
            TaskSourceKind.claudeCode.activationBundleIdentifiers,
            ["com.apple.Terminal", "com.googlecode.iterm2"]
        )
        XCTAssertEqual(
            TaskSourceKind.claudeCode.activationApplicationPaths,
            ["/System/Applications/Utilities/Terminal.app", "/Applications/iTerm.app"]
        )
    }

    func testOpenClawHasNoExternalActivationTargets() {
        XCTAssertTrue(TaskSourceKind.openClaw.activationBundleIdentifiers.isEmpty)
        XCTAssertTrue(TaskSourceKind.openClaw.activationApplicationPaths.isEmpty)
    }
}
