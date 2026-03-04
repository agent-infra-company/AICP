import Foundation
import UserNotifications

protocol NotificationService: AnyObject, Sendable {
    func prepare() async throws
    func sendTaskNeedsInput(_ task: TaskRecord) async
    func sendTaskCompleted(_ task: TaskRecord) async
    func sendTaskFailed(_ task: TaskRecord) async
}

final class UserNotificationService: NotificationService, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func prepare() async throws {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]
        _ = try await center.requestAuthorization(options: options)

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

    private func send(title: String, body: String, task: TaskRecord) async {
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
}
