import Foundation
import UserNotifications

protocol NotificationService: AnyObject, Sendable {
    func prepare() async throws
    func requestAuthorization() async throws -> Bool
    func sendTaskNeedsInput(_ task: TaskRecord) async
    func sendTaskCompleted(_ task: TaskRecord) async
    func sendTaskFailed(_ task: TaskRecord) async
    func sendExternalTaskNeedsInput(_ snapshot: ExternalTaskSnapshot) async
    func sendExternalTaskCompleted(_ snapshot: ExternalTaskSnapshot) async
    func sendExternalTaskFailed(_ snapshot: ExternalTaskSnapshot) async
}

final class UserNotificationService: NotificationService, @unchecked Sendable {
    private var center: UNUserNotificationCenter? {
        guard AppRuntimeEnvironment.current.supportsNotifications else { return nil }
        return UNUserNotificationCenter.current()
    }

    func prepare() async throws {
        guard let center else { return }
        let openAction = UNNotificationAction(
            identifier: "OPEN_TASK",
            title: "Open Task",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "TASK_EVENTS",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async throws -> Bool {
        guard let center else { return false }
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        return try await center.requestAuthorization(options: options)
    }

    func sendTaskNeedsInput(_ task: TaskRecord) async {
        await send(
            title: "Needs input",
            body: task.needsInputPrompt ?? task.title,
            task: task
        )
    }

    func sendTaskCompleted(_ task: TaskRecord) async {
        await send(
            title: "Task completed",
            body: task.title,
            task: task
        )
    }

    func sendTaskFailed(_ task: TaskRecord) async {
        await send(
            title: "Task needs attention",
            body: task.lastError ?? task.title,
            task: task
        )
    }

    func sendExternalTaskNeedsInput(_ snapshot: ExternalTaskSnapshot) async {
        await sendExternal(
            title: "\(snapshot.sourceKind.displayName): Needs input",
            body: snapshot.needsInputPrompt ?? snapshot.title,
            snapshot: snapshot
        )
    }

    func sendExternalTaskCompleted(_ snapshot: ExternalTaskSnapshot) async {
        await sendExternal(
            title: "\(snapshot.sourceKind.displayName): Task completed",
            body: snapshot.title,
            snapshot: snapshot
        )
    }

    func sendExternalTaskFailed(_ snapshot: ExternalTaskSnapshot) async {
        await sendExternal(
            title: "\(snapshot.sourceKind.displayName): Task needs attention",
            body: snapshot.lastError ?? snapshot.title,
            snapshot: snapshot
        )
    }

    private func send(title: String, body: String, task: TaskRecord) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "TASK_EVENTS"
        content.userInfo = ["taskId": task.taskId]

        let request = UNNotificationRequest(
            identifier: "task-\(task.taskId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            // Best-effort notifications.
        }
    }

    private func sendExternal(title: String, body: String, snapshot: ExternalTaskSnapshot) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "TASK_EVENTS"
        content.userInfo = [
            "taskId": snapshot.id,
            "sourceKind": snapshot.sourceKind.rawValue,
            "deepLinkURL": snapshot.deepLinkURL?.absoluteString ?? "",
        ]

        let request = UNNotificationRequest(
            identifier: "ext-\(snapshot.id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            // Best-effort notifications.
        }
    }
}
