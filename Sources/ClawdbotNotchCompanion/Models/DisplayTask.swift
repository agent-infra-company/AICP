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
}
