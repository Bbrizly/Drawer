import Foundation
import UserNotifications

enum FocusNotificationScheduler {
    private static let identifier = "drawer.focus.complete"

    static func schedule(taskTitle: String, seconds: TimeInterval) {
        guard seconds > 1 else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
            else { return }

            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let content = UNMutableNotificationContent()
            content.title = "Focus complete"
            content.body = taskTitle.isEmpty ? "Time's up." : taskTitle
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, seconds),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }
}
