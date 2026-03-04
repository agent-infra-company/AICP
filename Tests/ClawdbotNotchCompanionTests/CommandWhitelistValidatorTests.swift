import XCTest
@testable import ClawdbotNotchCompanion

final class CommandWhitelistValidatorTests: XCTestCase {
    func testValidatorAcceptsResolvedCommand() throws {
        let validator = CommandWhitelistValidator()
        let set = CommandTemplateSet(
            id: UUID(),
            name: "Test",
            startCmd: "start {{port}}",
            stopCmd: "stop",
            restartCmd: "restart {{port}}",
            statusCmd: "status",
            allowedPlaceholders: ["port"]
        )

        XCTAssertNoThrow(try validator.validate(action: .start, generatedCommand: "start 4689", templateSet: set))
    }

    func testValidatorRejectsUnresolvedPlaceholder() {
        let validator = CommandWhitelistValidator()
        let set = CommandTemplateSet.localDefault

        XCTAssertThrowsError(
            try validator.validate(
                action: .start,
                generatedCommand: "openclaw gateway start --port {{port}}",
                templateSet: set
            )
        )
    }
}
