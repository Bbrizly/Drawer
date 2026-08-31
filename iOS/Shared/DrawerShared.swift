import Foundation

enum DrawerShared {
    static let appGroupIdentifier = "group.com.bbrizly.drawer"
    static let bookmarkKey = "drawer.mobile.bookmark.v1"
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
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static func todayKey(now: Date = Date()) -> String {
        formatter.timeZone = .current
        return formatter.string(from: now)
    }

    static func tomorrowKey(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return todayKey(now: tomorrow)
    }

    static func dayAfter(_ dayKey: String) -> String? {
        formatter.timeZone = .current
        guard let date = formatter.date(from: dayKey),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: date)
        else { return nil }
        return formatter.string(from: next)
    }
}

enum DrawerTaskDestination: String, CaseIterable, Codable, Sendable {
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
