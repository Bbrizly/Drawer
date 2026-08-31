import DrawerCore
import Foundation

enum DrawerMutationEngine {
    enum MutationError: LocalizedError {
        case emptyTitle

        var errorDescription: String? {
            switch self {
            case .emptyTitle: "Task title can't be empty."
            }
        }
    }

    @discardableResult
    static func toggle(_ task: WidgetTask) throws -> WidgetSnapshot {
        let item = task.todoItem
        return try mutate { data in
            if try TodoRecurrenceWriteback.recurrence(for: item, in: data) != nil {
                // Widget and Shortcut completion must obey the same series
                // invariant as the app: complete the current occurrence and
                // create exactly one successor in the canonical Markdown.
                if item.isDone { return data }
                return try TodoRecurrenceWriteback.completeAndAdvance(
                    item: item,
                    today: DrawerDate.todayKey(),
                    in: data
                )
            }
            return try TodoWriteback.toggle(
                line: task.rawLine,
                sectionDate: task.sectionDate,
                occurrence: task.occurrence,
                in: data
            )
        }
    }

    @discardableResult
    static func complete(_ task: WidgetTask) throws -> WidgetSnapshot {
        if task.isDone { return WidgetSnapshotStore.read() }
        return try toggle(task)
    }

    @discardableResult
    static func add(
        title: String,
        destination: DrawerTaskDestination
    ) throws -> WidgetSnapshot {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MutationError.emptyTitle }
        let today = DrawerDate.todayKey()
        let tomorrow = DrawerDate.tomorrowKey()

        return try mutate(todayKey: today) { data in
            switch destination {
            case .today:
                return try TodoWriteback.append(title: title, today: today, in: data)
            case .tomorrow:
                return try TodoWriteback.insert(
                    line: "- [ ] " + title,
                    intoSectionKey: tomorrow,
                    displayHeading: tomorrow,
                    in: data
                )
            case .backlog:
                return try TodoWriteback.insert(
                    line: "- [ ] " + title,
                    intoSectionKey: TodoParser.backlogKey,
                    displayHeading: "Backlog",
                    in: data
                )
            }
        }
    }

    /// Same one-retry content CAS used by the Mac app: if Obsidian/iCloud
    /// changed the file after our first read, recompute the pure transform once
    /// against the fresh bytes instead of overwriting the external edit.
    private static func mutate(
        todayKey: String = DrawerDate.todayKey(),
        _ transform: (Data) throws -> Data
    ) throws -> WidgetSnapshot {
        let session = try DrawerBookmarkStore.openSession()
        var base = try session.read()
        var output = try transform(base)
        let fresh = try session.read()
        if fresh != base {
            base = fresh
            output = try transform(base)
        }

        try session.write(output)

        // Read once after the coordinated write. If a File Provider normalized
        // or another writer immediately changed the file, the widget cache shows
        // that truth rather than the bytes we merely attempted to write.
        let canonical = try session.read()
        let snapshot = WidgetSnapshot.make(from: canonical, todayKey: todayKey)
        try WidgetSnapshotStore.write(snapshot)
        return snapshot
    }
}

private extension WidgetTask {
    var todoItem: TodoItem {
        TodoItem(
            rawLine: rawLine,
            title: title,
            isDone: isDone,
            isInProgress: isInProgress,
            minutes: minutes,
            sectionDate: sectionDate,
            occurrence: occurrence
        )
    }
}
