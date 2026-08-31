import DrawerCore
import Foundation

struct WidgetTask: Codable, Hashable, Identifiable, Sendable {
    enum Bucket: String, Codable, Hashable, Sendable {
        case carried
        case today
        case upcoming
        case backlog
    }

    let id: String
    let title: String
    let rawLine: String
    let sectionDate: String
    let occurrence: Int
    let isDone: Bool
    let isInProgress: Bool
    let minutes: Int
    let bucket: Bucket

    init(
        id: String,
        title: String,
        rawLine: String,
        sectionDate: String,
        occurrence: Int,
        isDone: Bool,
        isInProgress: Bool,
        minutes: Int,
        bucket: Bucket
    ) {
        self.id = id
        self.title = title
        self.rawLine = rawLine
        self.sectionDate = sectionDate
        self.occurrence = occurrence
        self.isDone = isDone
        self.isInProgress = isInProgress
        self.minutes = minutes
        self.bucket = bucket
    }

    init(item: TodoItem, bucket: Bucket) {
        self.init(
            id: item.id,
            title: item.title,
            rawLine: item.rawLine,
            sectionDate: item.sectionDate,
            occurrence: item.occurrence,
            isDone: item.isDone,
            isInProgress: item.isInProgress,
            minutes: item.minutes,
            bucket: bucket
        )
    }
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let generatedAt: Date
    let sourceFingerprint: String
    let todayKey: String
    let upcomingLabel: String?
    let carried: [WidgetTask]
    let today: [WidgetTask]
    let upcoming: [WidgetTask]
    let backlog: [WidgetTask]

    var remaining: Int {
        (carried + today).filter { !$0.isDone }.count
    }

    var actionableTasks: [WidgetTask] {
        carried.filter { !$0.isDone } + today.filter { !$0.isDone }
    }

    var allTasks: [WidgetTask] {
        carried + today + upcoming + backlog
    }

    static func make(from data: Data, todayKey: String) -> WidgetSnapshot {
        let text = String(data: data, encoding: .utf8) ?? ""
        let display = TodoParser.display(
            sections: TodoParser.parse(text),
            today: todayKey
        )
        let tomorrow = DrawerDate.dayAfter(todayKey)
        let upcomingLabel: String? = display.upcomingDate.map { date in
            date == tomorrow ? "Tomorrow" : date
        }

        return WidgetSnapshot(
            version: schemaVersion,
            generatedAt: Date(),
            sourceFingerprint: fingerprint(data),
            todayKey: todayKey,
            upcomingLabel: upcomingLabel,
            carried: display.carried.map { WidgetTask(item: $0, bucket: .carried) },
            today: display.today.map { WidgetTask(item: $0, bucket: .today) },
            upcoming: display.upcoming.map { WidgetTask(item: $0, bucket: .upcoming) },
            backlog: display.backlog.map { WidgetTask(item: $0, bucket: .backlog) }
        )
    }

    static let empty = WidgetSnapshot(
        version: schemaVersion,
        generatedAt: .distantPast,
        sourceFingerprint: "0",
        todayKey: "",
        upcomingLabel: nil,
        carried: [],
        today: [],
        upcoming: [],
        backlog: []
    )

    private static func fingerprint(_ data: Data) -> String {
        // Stable, tiny and dependency-free. This is an invalidation fingerprint,
        // not a security hash.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum WidgetSnapshotStore {
    enum StoreError: Error {
        case appGroupUnavailable
    }

    static var snapshotURL: URL? {
        DrawerShared.containerURL?.appendingPathComponent(DrawerShared.snapshotFilename)
    }

    /// Reads only the App Group cache. This is deliberately cheap and never
    /// reaches a File Provider.
    static func read() -> WidgetSnapshot {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.schemaVersion
        else { return .empty }
        return snapshot
    }

    /// Best-effort canonical refresh for WidgetKit and App Intent queries.
    /// External Obsidian/iCloud edits and a new local day should appear even if
    /// the Drawer app itself has not launched. If the provider refuses access,
    /// if iCloud is still materializing the canonical file, or if the external
    /// file is temporarily invalid UTF-8, preserve the last known-good cache
    /// rather than manufacturing an empty or stale task state.
    static func current(todayKey: String = DrawerDate.todayKey()) -> WidgetSnapshot {
        let cached = read()
        do {
            let session = try DrawerBookmarkStore.openSession()
            let data = try session.read()
            guard String(data: data, encoding: .utf8) != nil else { return cached }
            let fresh = WidgetSnapshot.make(from: data, todayKey: todayKey)

            if cached.version == WidgetSnapshot.schemaVersion,
               cached.sourceFingerprint == fresh.sourceFingerprint,
               cached.todayKey == fresh.todayKey {
                return cached
            }

            try? write(fresh)
            return fresh
        } catch {
            return cached
        }
    }

    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url = snapshotURL else { throw StoreError.appGroupUnavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

struct WidgetInteractionFeedback: Equatable, Sendable {
    let message: String
    let occurredAt: Date
}

/// A widget mutation may fail even while its last snapshot remains valid—for
/// example when iCloud has evicted Drawer.md or a File Provider temporarily
/// refuses the extension's bookmark. Keep failure UI separate from task truth
/// so the widget can say "still old" without ever pretending the Markdown
/// mutation succeeded.
enum WidgetInteractionFeedbackStore {
    private static let messageKey = "drawer.widget.interaction-error.message.v1"
    private static let dateKey = "drawer.widget.interaction-error.date.v1"
    private static let lifetime: TimeInterval = 5 * 60

    static func recordFailure(_ error: Error) {
        let message: String
        if let accessError = error as? DrawerFileAccessError {
            message = accessError.widgetMessage
        } else if error is DrawerBookmarkError {
            message = "Open Drawer to reconnect Drawer.md."
        } else {
            message = "Update failed. Open Drawer and try again."
        }
        DrawerShared.defaults.set(message, forKey: messageKey)
        DrawerShared.defaults.set(Date().timeIntervalSince1970, forKey: dateKey)
    }

    static func clear() {
        DrawerShared.defaults.removeObject(forKey: messageKey)
        DrawerShared.defaults.removeObject(forKey: dateKey)
    }

    static func current(now: Date = Date()) -> WidgetInteractionFeedback? {
        guard let message = DrawerShared.defaults.string(forKey: messageKey) else { return nil }
        let timestamp = DrawerShared.defaults.double(forKey: dateKey)
        guard timestamp > 0 else {
            clear()
            return nil
        }
        let occurredAt = Date(timeIntervalSince1970: timestamp)
        guard now.timeIntervalSince(occurredAt) >= 0,
              now.timeIntervalSince(occurredAt) <= lifetime
        else {
            clear()
            return nil
        }
        return WidgetInteractionFeedback(message: message, occurredAt: occurredAt)
    }
}
