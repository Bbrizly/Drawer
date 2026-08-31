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
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    await DrawerActionFeedbackCenter.notice(
                        "Focus is running, but the completion alert couldn't be enabled.",
                        systemImage: "bell.slash.fill"
                    )
                    return
                }
                settings = await center.notificationSettings()
            }

            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
            else {
                await DrawerActionFeedbackCenter.notice(
                    "Focus is running; completion notifications are off.",
                    systemImage: "bell.slash.fill"
                )
                return
            }

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

            do {
                try await center.add(request)
            } catch {
                await DrawerActionFeedbackCenter.notice(
                    "Focus is running, but the completion alert couldn't be scheduled.",
                    systemImage: "bell.slash.fill"
                )
            }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }
}
