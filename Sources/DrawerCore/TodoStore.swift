import Combine
import Foundation

@MainActor
public final class TodoStore: ObservableObject {
    @Published public private(set) var todayItems: [TodoItem] = []
    @Published public private(set) var carriedItems: [TodoItem] = []
    @Published public private(set) var upcomingItems: [TodoItem] = []
    @Published public private(set) var upcomingLabel: String = ""
    @Published public private(set) var backlogItems: [TodoItem] = []
    @Published public private(set) var archiveItems: [TodoItem] = []
    @Published public private(set) var statusMessage: String?

    public private(set) var fileURL: URL
    private var watcher: FileWatcher
    private let todayProvider: @MainActor () -> String
    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void
    private var lastWrittenData: Data?
    /// The bytes the current display was parsed from. The watcher covers the
    /// whole directory, so sibling-file saves fire reloads constantly; when
    /// the drawer file itself is byte-identical, the parse and the publishes
    /// are skipped outright. Cleared on day change (display depends on today).
    private var lastAppliedData: Data?
    private var calendarObservers: [NSObjectProtocol] = []

    public convenience init(
        fileURL: URL,
        todayProvider: @escaping @MainActor () -> String = TodoStore.localToday
    ) {
        self.init(
            fileURL: fileURL,
            todayProvider: todayProvider,
            readData: { try Data(contentsOf: $0) },
            writeData: { try $0.write(to: $1, options: .atomic) }
        )
    }

    init(
        fileURL: URL,
        todayProvider: @escaping @MainActor () -> String,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.watcher = FileWatcher(
            directory: fileURL.deletingLastPathComponent(), pollFile: fileURL)
        self.todayProvider = todayProvider
        self.readData = readData
        self.writeData = writeData
    }

    /// Switches the backing file at runtime (settings change). Rewires the
    /// directory watcher and reloads immediately.
    public func updateFileURL(_ url: URL) {
        guard url != fileURL else { return }
        watcher.stop()
        fileURL = url
        lastWrittenData = nil
        lastAppliedData = nil
        watcher = FileWatcher(directory: url.deletingLastPathComponent(), pollFile: url)
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        reload()
    }

    /// One cached day formatter. Building a DateFormatter is the expensive
    /// part; re-assigning the time zone per call is cheap and keeps a system
    /// time zone change from going stale (the calendar observers reload, and
    /// this picks up the new zone on the next call).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        // POSIX locale so day keys are Gregorian on any system calendar.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    public static func localToday() -> String {
        dayFormatter.timeZone = .current
        return dayFormatter.string(from: Date())
    }

    public func start() {
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        startCalendarObservers()
        reload()
    }

    public func stop() {
        watcher.stop()
        calendarObservers.forEach(NotificationCenter.default.removeObserver)
        calendarObservers.removeAll()
    }

    public func reload() {
        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            todayItems = []
            carriedItems = []
            upcomingItems = []
            upcomingLabel = ""
            backlogItems = []
            archiveItems = []
            statusMessage = Self.isMissingFileError(error)
                ? "No drawer file yet"
                : "Could not read drawer file"
            lastAppliedData = nil
            return
        }
        // Self-write suppression: skip reload churn for our own write.
        if let last = lastWrittenData {
            lastWrittenData = nil
            if data == last { return }
        }
        // Sibling-file suppression: the directory watcher fired but the drawer
        // file itself did not change, so what is displayed is already right.
        if data == lastAppliedData { return }
        // Sweep done tasks older than the keep window into Archive > Done.
        // Idempotent and only writes when something actually moved, so the
        // follow-up watcher event is caught by the suppression check above.
        if let text = String(data: data, encoding: .utf8) {
            let swept = TodoArchiver.archiveCompleted(in: text, today: todayProvider())
            if swept != text, let sweptData = swept.data(using: .utf8) {
                do {
                    lastWrittenData = sweptData
                    try writeData(sweptData, fileURL)
                    apply(sweptData)
                    return
                } catch {
                    lastWrittenData = nil
                    // Fall through and show the data we already read.
                }
            }
        }
        apply(data)
    }

    public func toggle(_ item: TodoItem) {
        mutate { data in
            try TodoWriteback.toggle(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
        }
    }

    public func delete(_ item: TodoItem) {
        mutate { data in
            try TodoWriteback.delete(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
        }
    }

    /// Looks up a currently displayed item by its id, across every section.
    /// Lets the swipe coordinator act on a row it only knows by id.
    public func item(withID id: String) -> TodoItem? {
        for items in [todayItems, carriedItems, upcomingItems, backlogItems, archiveItems] {
            if let hit = items.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    public func setInProgress(_ item: TodoItem, _ inProgress: Bool) {
        mutate { data in
            try TodoWriteback.setInProgress(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                inProgress: inProgress,
                in: data
            )
        }
    }

    public func setNote(_ item: TodoItem, _ note: String) {
        mutate { data in
            try TodoWriteback.setNote(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                note: note,
                in: data
            )
        }
    }

    /// Reads, runs a writeback transform, and writes with a one-shot content-CAS:
    /// if the file changed between our read and the write (a concurrent
    /// Obsidian/iCloud/MCP save), the transform is recomputed once against the
    /// fresh bytes so that edit is not clobbered. The writeback transforms locate
    /// their target by section + occurrence + exact rawLine, so replaying against
    /// fresh bytes hits the same logical task. `lastWrittenData` is set only after
    /// the write succeeds, so a thrown write never leaves a stale suppression
    /// value that swallows the next external reload.
    /// ponytail: one re-read, not a loop or a file lock. A single external editor
    /// is the only other writer in practice; upgrade to NSFileCoordinator if
    /// cross-process races ever matter.
    private func commit(readingMissingAsEmpty: Bool = false, _ transform: (Data) throws -> Data) throws {
        func currentData() throws -> Data {
            do { return try readData(fileURL) }
            catch where readingMissingAsEmpty && Self.isMissingFileError(error) { return Data() }
        }
        var data = try currentData()
        var newData = try transform(data)
        let fresh = try currentData()
        if fresh != data {
            data = fresh
            newData = try transform(data)
        }
        try writeData(newData, fileURL)
        lastWrittenData = newData
        apply(newData)
    }

    /// Runs a writeback transform against the file. On any failure (a stale line,
    /// a vanished file, a write error) it never guesses: it drops the self-write
    /// guard and reloads the truth on disk.
    private func mutate(_ transform: (Data) throws -> Data) {
        do {
            try commit(transform)
        } catch {
            lastWrittenData = nil
            reload()
        }
    }

    /// Commits a day plan through the shared PlanWriter (the same path the MCP
    /// server uses). Throws PlanWriter's validation errors so the caller can
    /// surface a rejection instead of silently doing nothing.
    public func writeDayPlan(date: String, entries: [PlanEntry], replace: Bool) throws {
        try commit(readingMissingAsEmpty: true) { data in
            try PlanWriter.write(date: date, entries: entries, replace: replace, in: data)
        }
    }

    public func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Capture today once: the CAS transform may run twice, and it must not
        // roll to a new day between the two passes.
        let today = todayProvider()
        do {
            try commit(readingMissingAsEmpty: true) { data in
                try TodoWriteback.append(title: trimmed, today: today, in: data)
            }
        } catch {
            lastWrittenData = nil
            statusMessage = "Could not save drawer file"
        }
    }

    /// Adds a task to any section (e.g. Backlog, Archive), creating the section
    /// with `displayHeading` if it does not exist yet.
    public func addTask(_ title: String, toSectionKey key: String, displayHeading: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        insertLine("- [ ] " + trimmed, intoSectionKey: key, displayHeading: displayHeading)
    }

    /// Adds a "### " subheading to a section, to group the tasks below it.
    public func addHeader(_ title: String, toSectionKey key: String, displayHeading: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        insertLine("### " + trimmed, intoSectionKey: key, displayHeading: displayHeading)
    }

    private func insertLine(_ line: String, intoSectionKey key: String, displayHeading: String) {
        do {
            try commit(readingMissingAsEmpty: true) { data in
                try TodoWriteback.insert(
                    line: line, intoSectionKey: key, displayHeading: displayHeading, in: data)
            }
        } catch {
            lastWrittenData = nil
            statusMessage = "Could not save drawer file"
        }
    }

    /// Renames a task in place, writing the new title back to its line.
    public func rename(_ item: TodoItem, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        mutate { data in
            try TodoWriteback.rename(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                to: trimmed,
                in: data
            )
        }
    }

    private func apply(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            statusMessage = "File is not UTF-8"
            lastAppliedData = nil
            return
        }
        let today = todayProvider()
        let display = TodoParser.display(
            sections: TodoParser.parse(text),
            today: today
        )
        // Publish only what actually changed. An edit usually touches one
        // section; the other five publishes would re-evaluate every
        // subscriber's body for nothing. The compares are cheap value
        // equality on the visible items.
        if todayItems != display.today { todayItems = display.today }
        if carriedItems != display.carried { carriedItems = display.carried }
        if upcomingItems != display.upcoming { upcomingItems = display.upcoming }
        if backlogItems != display.backlog { backlogItems = display.backlog }
        if archiveItems != display.archive { archiveItems = display.archive }
        let label: String
        if let next = display.upcomingDate {
            label = next == Self.dayAfter(today) ? "Tomorrow" : next
        } else {
            label = ""
        }
        if upcomingLabel != label { upcomingLabel = label }
        if statusMessage != nil { statusMessage = nil }
        lastAppliedData = data
    }

    static func dayAfter(_ date: String) -> String? {
        dayFormatter.timeZone = .current
        guard let d = dayFormatter.date(from: date),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: d)
        else { return nil }
        return dayFormatter.string(from: next)
    }

    private func startCalendarObservers() {
        guard calendarObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
        ]
        calendarObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    // Both caches must go: "today" changed, so identical bytes
                    // no longer mean an identical display.
                    self?.lastWrittenData = nil
                    self?.lastAppliedData = nil
                    self?.reload()
                }
            }
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == CocoaError.fileReadNoSuchFile.rawValue
    }
}
