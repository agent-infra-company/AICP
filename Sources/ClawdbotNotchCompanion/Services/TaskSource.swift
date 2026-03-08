import AppKit
import Foundation

enum TaskSourceKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case openClaw = "openclaw"
    case conductor = "conductor"
    case claudeCode = "claude_code"
    case codex = "codex"
    case claudeDesktop = "claude_desktop"
    case cursor = "cursor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openClaw: "OpenClaw"
        case .conductor: "Conductor"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .claudeDesktop: "Claude Desktop"
        case .cursor: "Cursor"
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
