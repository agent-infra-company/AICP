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
}
