import Foundation

struct CommandWhitelistValidator {
    func validate(
        action: RuntimeAction,
        generatedCommand: String,
        templateSet: CommandTemplateSet
    ) throws {
        let sourceTemplate = templateSet.command(for: action).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTemplate.isEmpty else {
            throw RuntimeManagerError.commandRejected("Missing command template for action \(action.rawValue).")
        }

        guard !generatedCommand.contains("{{"), !generatedCommand.contains("}}") else {
            throw RuntimeManagerError.commandRejected("Generated command contains unresolved placeholders.")
        }

        let disallowed = ["\n", "\r", "\u{0}"]
        if disallowed.contains(where: { generatedCommand.contains($0) }) {
            throw RuntimeManagerError.commandRejected("Generated command contains disallowed control characters.")
        }
    }
}
