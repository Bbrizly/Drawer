import ActivityKit
import Foundation

enum DrawerShared {
    static let appGroupIdentifier = "group.com.bbrizly.drawer"
    static let bookmarkKey = "drawer.mobile.bookmark.v1"
    static let pendingBookmarkKey = "drawer.mobile.bookmark.pending.v1"
    static let snapshotFilename = "drawer-widget-snapshot-v1.json"
    static let focusSessionKey = "drawer.focus.session.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }
}

struct DrawerPersistedFocus: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case running
        case paused
        case finished
    }

    let id: UUID
    let taskTitle: String
    let phase: Phase
    let endDate: Date?
    let remaining: TimeInterval
    let createdAt: Date
}

/// Shared by the app and widget extension so Focus can leave the app without
/// creating a second timer. Running state carries an absolute end date; the
/// system renders the countdown itself even while Drawer is suspended.
struct DrawerFocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case running
            case paused
            case finished
            case ended
        }

        let phase: Phase
        let endDate: Date?
        let remaining: TimeInterval
    }

    let sessionID: UUID
    let taskTitle: String
}

enum DrawerFocusStore {
    static func load() -> DrawerPersistedFocus? {
        guard let data = DrawerShared.defaults.data(forKey: DrawerShared.focusSessionKey) else { return nil }
        return try? JSONDecoder().decode(DrawerPersistedFocus.self, from: data)
    }

    static func save(_ focus: DrawerPersistedFocus) {
        guard let data = try? JSONEncoder().encode(focus) else { return }
        DrawerShared.defaults.set(data, forKey: DrawerShared.focusSessionKey)
    }

    static func clear() {
        DrawerShared.defaults.removeObject(forKey: DrawerShared.focusSessionKey)
    }
}

enum DrawerDate {
    /// No shared DateFormatter: widgets and App Intents can execute on different
    /// concurrency domains in the same process. Calendar values are local and
    /// therefore cannot race while the system time zone changes.
    private static func gregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }

    static func todayKey(now: Date = Date()) -> String {
        let components = gregorianCalendar().dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func tomorrowKey(now: Date = Date()) -> String {
        let calendar = gregorianCalendar()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return todayKey(now: tomorrow)
    }

    static func dayAfter(_ dayKey: String) -> String? {
        let pieces = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }

        let calendar = gregorianCalendar()
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day,
              let next = calendar.date(byAdding: .day, value: 1, to: date)
        else { return nil }
        return todayKey(now: next)
    }
}

enum DrawerTaskDestination: String, CaseIterable, Codable, Hashable, Sendable {
    case today
    case tomorrow
    case backlog

    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .backlog: "Backlog"
        }
    }
}
