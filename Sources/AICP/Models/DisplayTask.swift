import Foundation

struct DisplayTask: Identifiable, Hashable {
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

    init(
        id: String,
        sourceKind: TaskSourceKind,
        title: String,
        workspace: String?,
        status: TaskStatus,
        progress: String?,
        needsInputPrompt: String?,
        lastError: String?,
        updatedAt: Date,
        deepLinkURL: URL?,
        metadata: [String: String]
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.title = title
        self.workspace = workspace
        self.status = status
        self.progress = progress
        self.needsInputPrompt = needsInputPrompt
        self.lastError = lastError
        self.updatedAt = updatedAt
        self.deepLinkURL = deepLinkURL
        self.metadata = metadata
    }

    init(from record: TaskRecord, profiles: [ProfileConfig]) {
        self.id = "openclaw-\(record.taskId)"
        self.sourceKind = .openClaw
        self.title = record.title
        self.workspace = profiles.first(where: { $0.id == record.profileId })?.name
        self.status = record.status
        self.progress = record.latestProgress
        self.needsInputPrompt = record.needsInputPrompt
        self.lastError = record.lastError
        self.updatedAt = record.updatedAt
        self.deepLinkURL = nil
        self.metadata = ["routeId": record.routeId]
    }

    init(from snapshot: ExternalTaskSnapshot) {
        self.id = "\(snapshot.sourceKind.rawValue)-\(snapshot.id)"
        self.sourceKind = snapshot.sourceKind
        self.title = snapshot.title
        self.workspace = snapshot.workspace
        self.status = snapshot.status
        self.progress = snapshot.progress
        self.needsInputPrompt = snapshot.needsInputPrompt
        self.lastError = snapshot.lastError
        self.updatedAt = snapshot.updatedAt
        self.deepLinkURL = snapshot.deepLinkURL
        self.metadata = snapshot.metadata
    }

    /// Sort priority: lower values appear first in the task list.
    var sortPriority: Int {
        switch status {
        case .running: return 0
        case .queued: return 1
        case .needsInput: return 2
        case .needsAttention: return 3
        case .draft: return 4
        case .completed, .failed, .canceled: return 5
        }
    }

    var statusText: String {
        if let progress {
            return progress
        }
        switch status {
        case .running: return "Working..."
        case .queued: return "Queued"
        case .needsInput: return "Needs input"
        case .completed: return "Done"
        case .failed: return "Error"
        case .needsAttention: return "Attention"
        case .canceled: return "Canceled"
        case .draft: return "Draft"
        }
    }

    /// Whether this task is a CLI session running in a terminal.
    var isTerminalSession: Bool {
        if sourceKind == .claudeCode { return true }
        if sourceKind == .codex, metadata["source"] == "cli" { return true }
        return false
    }

    /// The icon image name to display, accounting for CLI sessions.
    /// Terminal sessions show the terminal icon; app sessions show the app icon.
    var resolvedIconImageName: String? {
        if isTerminalSession { return "icon_terminal" }
        return sourceKind.iconImageName
    }

    /// Short agent label shown alongside the terminal icon so the user
    /// can tell which agent is running (e.g. "Claude Code" vs "Codex").
    var agentLabel: String? {
        guard isTerminalSession else { return nil }
        return sourceKind.displayName
    }

    /// User-facing workspace/location label shown in the task row.
    /// Conductor workspaces are clearer when identified by branch, since
    /// `directory_name` is often just the ephemeral workspace folder name.
    var locationLabel: String? {
        if sourceKind == .conductor, let branch = metadata["branch"], !branch.isEmpty {
            return branch
        }
        return workspace
    }

    var activationBundleIdentifiers: [String] {
        if sourceKind == .codex, metadata["source"] == "cli" {
            return TaskSourceKind.claudeCode.activationBundleIdentifiers
        }
        if sourceKind == .webAIChat, let browser = metadata["browser"] {
            return [browser]
        }
        return sourceKind.activationBundleIdentifiers
    }

    var activationApplicationPaths: [String] {
        if sourceKind == .codex, metadata["source"] == "cli" {
            return TaskSourceKind.claudeCode.activationApplicationPaths
        }
        if sourceKind == .webAIChat, let browserName = metadata["browserName"] {
            return ["/Applications/\(browserName).app"]
        }
        return sourceKind.activationApplicationPaths
    }
}
