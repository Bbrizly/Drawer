import Foundation

enum DrawerShared {
    static let appGroupIdentifier = "group.com.bbrizly.drawer"
    static let bookmarkKey = "drawer.mobile.bookmark.v1"
    static let snapshotFilename = "drawer-widget-snapshot-v1.json"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
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
