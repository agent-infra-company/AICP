import XCTest
@testable import AICP

final class CommandTemplateEngineTests: XCTestCase {
    func testRenderReplacesAllowedPlaceholders() throws {
        let engine = CommandTemplateEngine()
        let rendered = try engine.render(
            template: "openclaw gateway start --port {{port}}",
            values: ["port": "4689"],
            allowedPlaceholders: ["port"]
        )

        XCTAssertEqual(rendered, "openclaw gateway start --port 4689")
    }

    func testRenderRejectsUnknownPlaceholder() {
        let engine = CommandTemplateEngine()

        XCTAssertThrowsError(
            try engine.render(
                template: "cmd {{danger}}",
                values: ["danger": "x"],
                allowedPlaceholders: ["port"]
            )
        )
    }

    func testRenderRejectsUnsafeValue() {
        let engine = CommandTemplateEngine()

        XCTAssertThrowsError(
            try engine.render(
                template: "cmd --host {{host}}",
                values: ["host": "host; rm -rf /"],
                allowedPlaceholders: ["host"]
            )
        )
    }
}
