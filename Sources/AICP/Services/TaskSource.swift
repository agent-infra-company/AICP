import AppKit
import Foundation

enum TaskSourceKind: Codable, Identifiable, Hashable {
    case openClaw
    case conductor
    case claudeCode
    case codex
    case claudeDesktop
    case cursor
    case webAIChat
    case custom(String)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .openClaw: "openclaw"
        case .conductor: "conductor"
        case .claudeCode: "claude_code"
        case .codex: "codex"
        case .claudeDesktop: "claude_desktop"
        case .cursor: "cursor"
        case .webAIChat: "web_ai_chat"
        case .custom(let id): "custom_\(id)"
        }
    }

    /// All built-in cases (for iteration where CaseIterable was used).
    static var builtInCases: [TaskSourceKind] {
        [.openClaw, .conductor, .claudeCode, .codex, .claudeDesktop, .cursor, .webAIChat]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = Self.from(rawValue: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Parse a raw string back to a TaskSourceKind, falling back to .custom for unknown values.
    static func from(rawValue: String) -> TaskSourceKind {
        switch rawValue {
        case "openclaw": .openClaw
        case "conductor": .conductor
        case "claude_code": .claudeCode
        case "codex": .codex
        case "claude_desktop": .claudeDesktop
        case "cursor": .cursor
        case "web_ai_chat": .webAIChat
        default:
            if rawValue.hasPrefix("custom_") {
                .custom(String(rawValue.dropFirst("custom_".count)))
            } else {
                .custom(rawValue)
            }
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var customId: String? {
        if case .custom(let id) = self { return id }
        return nil
    }

    var displayName: String {
        switch self {
        case .openClaw: "OpenClaw"
        case .conductor: "Conductor"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
        case .webAIChat: "Web AI"
        case .custom(let id): id
        }
    }

    var iconName: String {
        switch self {
        case .openClaw: "network"
        case .conductor: "music.note.list"
        case .claudeCode: "terminal"
        case .codex: "doc.text.magnifyingglass"
        case .claudeDesktop: "bubble.left.and.bubble.right"
        case .cursor: "chevron.left.forwardslash.chevron.right"
        case .webAIChat: "globe"
        case .custom: "puzzlepiece.extension"
        }
    }

    /// Resource image name for the app icon PNG, if available.
    var iconImageName: String? {
        switch self {
        case .conductor: "icon_conductor"
        case .claudeCode: "icon_claude_code"
        case .codex: "icon_codex"
        case .claudeDesktop: "icon_claude"
        case .cursor: "icon_cursor"
        case .openClaw: nil
        case .webAIChat: nil
        case .custom: nil
        }
    }

    var iconColor: String {
        switch self {
        case .openClaw: "blue"
        case .conductor: "purple"
        case .claudeCode: "green"
        case .codex: "teal"
        case .claudeDesktop: "orange"
        case .cursor: "indigo"
        case .webAIChat: "cyan"
        case .custom: "gray"
        }
    }

    /// Hex color value for the icon.
    var iconColorHexValue: String {
        switch self {
        case .openClaw: "#007AFF"
        case .conductor: "#AF52DE"
        case .claudeCode: "#34C759"
        case .codex: "#5AC8FA"
        case .claudeDesktop: "#FF9500"
        case .cursor: "#5856D6"
        case .webAIChat: "#32D5D0"
        case .custom: "#888888"
        }
    }

    var urlScheme: String? {
        switch self {
        case .openClaw: nil
        case .conductor: "conductor"
        case .claudeCode: nil
        case .codex: "codex"
        case .claudeDesktop: "claude"
        case .cursor: nil
        case .webAIChat: nil
        case .custom: nil
        }
    }

    var activationBundleIdentifiers: [String] {
        switch self {
        case .openClaw:
            []
        case .conductor:
            ["com.conductor.app"]
        case .claudeCode:
            ["com.apple.Terminal", "com.googlecode.iterm2"]
        case .codex:
            ["com.openai.codex"]
        case .claudeDesktop:
            ["com.anthropic.claudefordesktop"]
        case .cursor:
            ["com.todesktop.230313mzl4w4u92"]
        case .webAIChat:
            [
                "com.google.Chrome",
                "com.apple.Safari",
                "company.thebrowser.Browser",
                "com.brave.Browser",
                "com.microsoft.edgemac",
            ]
        case .custom:
            []
        }
    }

    var activationApplicationPaths: [String] {
        switch self {
        case .openClaw:
            []
        case .conductor:
            ["/Applications/Conductor.app"]
        case .claudeCode:
            ["/System/Applications/Utilities/Terminal.app", "/Applications/iTerm.app"]
        case .codex:
            ["/Applications/Codex.app"]
        case .claudeDesktop:
            ["/Applications/Claude.app"]
        case .cursor:
            ["/Applications/Cursor.app"]
        case .webAIChat:
            [
                "/Applications/Google Chrome.app",
                "/Applications/Safari.app",
                "/Applications/Arc.app",
                "/Applications/Brave Browser.app",
                "/Applications/Microsoft Edge.app",
            ]
        case .custom:
            []
        }
    }
}

struct ExternalTaskSnapshot: Identifiable, Hashable {
    let id: String
    let sourceKind: TaskSourceKind
    let title: String
    let workspace: String?
    let status: TaskStatus
    let progress: String?
    let needsInputPrompt: String?
    let lastError: String?
    let updatedAt: Date
    let deepLinkURL: URL?
    let metadata: [String: String]
}

protocol TaskSource: AnyObject, Sendable {
    var sourceKind: TaskSourceKind { get }
    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]>
    func stopMonitoring() async
    func isAvailable() async -> Bool
}
