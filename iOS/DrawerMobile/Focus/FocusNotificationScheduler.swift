import ActivityKit
import Foundation
import UserNotifications

@MainActor
enum FocusNotificationScheduler {
    private static let identifier = "drawer.focus.complete"
    private static var generation: UInt = 0

    static func schedule(taskTitle: String, seconds: TimeInterval) {
        generation &+= 1
        let scheduledGeneration = generation
        let scheduledSessionID = DrawerFocusStore.load()?.id

        reconcileLiveActivity()

        // A new Focus replaces the one global completion alert. Remove the old
        // request before any notification-settings/authorization suspension so
        // a prior session can never survive while the new schedule is waiting.
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )

        guard seconds > 1, let scheduledSessionID else { return }

        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            var settings = await center.notificationSettings()

            guard isCurrentRunningSchedule(
                generation: scheduledGeneration,
                sessionID: scheduledSessionID
            ) else { return }

            if settings.authorizationStatus == .notDetermined {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    guard isCurrentRunningSchedule(
                        generation: scheduledGeneration,
                        sessionID: scheduledSessionID
                    ) else { return }
                    DrawerActionFeedbackCenter.notice(
                        "Focus is running, but the completion alert couldn't be enabled.",
                        systemImage: "bell.slash.fill"
                    )
                    return
                }

                guard isCurrentRunningSchedule(
                    generation: scheduledGeneration,
                    sessionID: scheduledSessionID
                ) else { return }

                settings = await center.notificationSettings()
            }

            guard isCurrentRunningSchedule(
                generation: scheduledGeneration,
                sessionID: scheduledSessionID
            ) else { return }

            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
            else {
                DrawerActionFeedbackCenter.notice(
                    "Focus is running; completion notifications are off.",
                    systemImage: "bell.slash.fill"
                )
                return
            }

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

                guard isCurrentRunningSchedule(
                    generation: scheduledGeneration,
                    sessionID: scheduledSessionID
                ) else {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    return
                }
            } catch {
                guard isCurrentRunningSchedule(
                    generation: scheduledGeneration,
                    sessionID: scheduledSessionID
                ) else { return }
                DrawerActionFeedbackCenter.notice(
                    "Focus is running, but the completion alert couldn't be scheduled.",
                    systemImage: "bell.slash.fill"
                )
            }
        }
    }

    static func cancel() {
        generation &+= 1
        reconcileLiveActivity()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
    }

    private static func isCurrentRunningSchedule(
        generation scheduledGeneration: UInt,
        sessionID: UUID
    ) -> Bool {
        guard generation == scheduledGeneration,
              let current = DrawerFocusStore.load(),
              current.id == sessionID,
              current.phase == .running
        else { return false }
        return true
    }

    private static func reconcileLiveActivity() {
        let persistedFocus = DrawerFocusStore.load()
        Task {
            await DrawerFocusLiveActivityManager.shared.reconcile(persistedFocus)
        }
    }
}

/// Serializes ActivityKit mutations so rapid pause/resume taps cannot reorder
/// Live Activity state. It only mirrors DrawerFocusStore; it never owns timer
/// truth and never completes a Markdown task.
actor DrawerFocusLiveActivityManager {
    static let shared = DrawerFocusLiveActivityManager()

    func reconcile(_ focus: DrawerPersistedFocus?) async {
        guard let focus else {
            await endAll(immediately: true)
            return
        }

        let matching = Activity<DrawerFocusActivityAttributes>.activities.first {
            $0.attributes.sessionID == focus.id
        }

        for activity in Activity<DrawerFocusActivityAttributes>.activities
        where activity.attributes.sessionID != focus.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        switch focus.phase {
        case .running:
            guard let endDate = focus.endDate else {
                if let matching { await matching.end(nil, dismissalPolicy: .immediate) }
                return
            }
            if endDate <= Date() {
                await finishExisting(matching, remaining: 0)
            } else if let matching {
                await matching.update(
                    ActivityContent(
                        state: .init(phase: .running, endDate: endDate, remaining: focus.remaining),
                        staleDate: endDate
                    )
                )
            } else {
                await start(focus, endDate: endDate)
            }

        case .paused:
            if let matching {
                await matching.update(
                    ActivityContent(
                        state: .init(phase: .paused, endDate: nil, remaining: focus.remaining),
                        staleDate: nil
                    )
                )
            } else {
                await start(focus, endDate: nil)
            }

        case .finished:
            await finishExisting(matching, remaining: 0)
        }
    }

    func end(sessionID: UUID?, completed: Bool) async {
        let activities = Activity<DrawerFocusActivityAttributes>.activities.filter {
            sessionID == nil || $0.attributes.sessionID == sessionID
        }
        let phase: DrawerFocusActivityAttributes.ContentState.Phase = completed ? .finished : .ended
        let final = ActivityContent(
            state: DrawerFocusActivityAttributes.ContentState(
                phase: phase,
                endDate: nil,
                remaining: 0
            ),
            staleDate: nil
        )
        let policy: ActivityUIDismissalPolicy = completed
            ? .after(Date().addingTimeInterval(5 * 60))
            : .immediate

        for activity in activities {
            await activity.end(final, dismissalPolicy: policy)
        }
    }

    private func start(_ focus: DrawerPersistedFocus, endDate: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let phase: DrawerFocusActivityAttributes.ContentState.Phase = endDate == nil ? .paused : .running
        let attributes = DrawerFocusActivityAttributes(
            sessionID: focus.id,
            taskTitle: focus.taskTitle
        )
        let state = DrawerFocusActivityAttributes.ContentState(
            phase: phase,
            endDate: endDate,
            remaining: focus.remaining
        )

        do {
            _ = try Activity<DrawerFocusActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: endDate),
                pushType: nil
            )
        } catch {
            // Live Activities are an ambient enhancement. Focus remains fully
            // functional if the user disabled them or ActivityKit refuses one.
        }
    }

    private func finishExisting(
        _ activity: Activity<DrawerFocusActivityAttributes>?,
        remaining: TimeInterval
    ) async {
        guard let activity else { return }
        let final = ActivityContent(
            state: DrawerFocusActivityAttributes.ContentState(
                phase: .finished,
                endDate: nil,
                remaining: remaining
            ),
            staleDate: nil
        )
        await activity.end(
            final,
            dismissalPolicy: .after(Date().addingTimeInterval(5 * 60))
        )
    }

    private func endAll(immediately: Bool) async {
        for activity in Activity<DrawerFocusActivityAttributes>.activities {
            await activity.end(
                nil,
                dismissalPolicy: immediately ? .immediate : .default
            )
        }
    }
}
