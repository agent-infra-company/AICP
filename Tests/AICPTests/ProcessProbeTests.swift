import XCTest
import os.log
@testable import AICP

final class ProcessProbeTests: XCTestCase {
    func testRunDrainsLargeStdoutWithoutDeadlocking() async throws {
        let finished = expectation(description: "process probe returns")
        let logger = Logger(subsystem: "com.aicp.app.tests", category: "ProcessProbeTests")

        final class Box: @unchecked Sendable {
            var output: String?
        }

        let box = Box()

        DispatchQueue.global(qos: .userInitiated).async {
            box.output = ProcessProbe.run(
                path: "/usr/bin/jot",
                arguments: ["40000"],
                logger: logger,
                label: "jot"
            )
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 2.0)
        XCTAssertNotNil(box.output)
        XCTAssertTrue(box.output?.hasPrefix("1\n2\n3\n") == true)
    }
}
