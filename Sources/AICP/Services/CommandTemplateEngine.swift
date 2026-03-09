import Foundation

enum CommandTemplateEngineError: Error, LocalizedError {
    case unresolvedPlaceholder(String)
    case placeholderNotAllowed(String)
    case unsafePlaceholderValue(String)

    var errorDescription: String? {
        switch self {
        case let .unresolvedPlaceholder(name):
            "Missing value for placeholder {{\(name)}}"
        case let .placeholderNotAllowed(name):
            "Placeholder {{\(name)}} is not allowed in this command template set."
        case let .unsafePlaceholderValue(name):
            "Placeholder \(name) contains unsupported characters."
        }
    }
}

struct CommandTemplateEngine {
    private let pattern = #"\{\{([a-zA-Z0-9_]+)\}\}"#
    private let allowedValuePattern = #"^[a-zA-Z0-9._:/@\-]+$"#

    func render(template: String, values: [String: String], allowedPlaceholders: [String]) throws -> String {
        let allowed = Set(allowedPlaceholders)
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: template.utf16.count))

        var rendered = template
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: template) else { continue }
            let key = String(template[range])
            guard allowed.contains(key) else {
                throw CommandTemplateEngineError.placeholderNotAllowed(key)
            }
            guard let value = values[key] else {
                throw CommandTemplateEngineError.unresolvedPlaceholder(key)
            }
            guard value.range(of: allowedValuePattern, options: .regularExpression) != nil else {
                throw CommandTemplateEngineError.unsafePlaceholderValue(key)
            }
            guard let replacementRange = Range(match.range(at: 0), in: rendered) else { continue }
            rendered.replaceSubrange(replacementRange, with: value)
        }

        return rendered
    }
}
