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
        case .needsInput, .needsAttention: return 0
        case .running: return 1
        case .queued: return 2
        case .draft: return 3
        case .completed: return 4
        case .failed: return 4
        case .canceled: return 4
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
