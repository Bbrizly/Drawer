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
        self.watcher = FileWatcher(directory: fileURL.deletingLastPathComponent())
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
        watcher = FileWatcher(directory: url.deletingLastPathComponent())
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        reload()
    }

    public static func localToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
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
            return
        }
        // Self-write suppression: skip reload churn for our own write.
        if let last = lastWrittenData {
            lastWrittenData = nil
            if data == last { return }
        }
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
        do {
            let data = try readData(fileURL)
            let newData = try TodoWriteback.toggle(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
            lastWrittenData = newData
            try writeData(newData, fileURL)
            apply(newData)
        } catch {
            // Stale line, vanished file, write failure: never guess. Reload truth.
            lastWrittenData = nil
            reload()
        }
    }

    public func delete(_ item: TodoItem) {
        do {
            let data = try readData(fileURL)
            let newData = try TodoWriteback.delete(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                in: data
            )
            lastWrittenData = newData
            try writeData(newData, fileURL)
            apply(newData)
        } catch {
            // Stale line, vanished file, write failure: never guess. Reload truth.
            lastWrittenData = nil
            reload()
        }
    }

    /// Looks up a currently displayed item by its id, across every section.
    /// Lets the swipe coordinator act on a row it only knows by id.
    public func item(withID id: String) -> TodoItem? {
        let all = todayItems + carriedItems + upcomingItems + backlogItems + archiveItems
        return all.first { $0.id == id }
    }

    public func setInProgress(_ item: TodoItem, _ inProgress: Bool) {
        do {
            let data = try readData(fileURL)
            let newData = try TodoWriteback.setInProgress(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                inProgress: inProgress,
                in: data
            )
            lastWrittenData = newData
            try writeData(newData, fileURL)
            apply(newData)
        } catch {
            // Stale line, vanished file, write failure: never guess. Reload truth.
            lastWrittenData = nil
            reload()
        }
    }

    public func setNote(_ item: TodoItem, _ note: String) {
        do {
            let data = try readData(fileURL)
            let newData = try TodoWriteback.setNote(
                line: item.rawLine,
                sectionDate: item.sectionDate,
                occurrence: item.occurrence,
                note: note,
                in: data
            )
            lastWrittenData = newData
            try writeData(newData, fileURL)
            apply(newData)
        } catch {
            // Stale line, vanished file, write failure: never guess. Reload truth.
            lastWrittenData = nil
            reload()
        }
    }

    public func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let data: Data
        do {
            data = try readData(fileURL)
        } catch where Self.isMissingFileError(error) {
            data = Data()
        } catch {
            statusMessage = "Could not read drawer file"
            return
        }

        do {
            let newData = try TodoWriteback.append(
                title: trimmed, today: todayProvider(), in: data
            )
            lastWrittenData = newData
            try writeData(newData, fileURL)
            apply(newData)
        } catch {
            lastWrittenData = nil
            statusMessage = "Could not save drawer file"
        }
    }

    private func apply(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            statusMessage = "File is not UTF-8"
            return
        }
        let today = todayProvider()
        let display = TodoParser.display(
            sections: TodoParser.parse(text),
            today: today
        )
        todayItems = display.today
        carriedItems = display.carried
        upcomingItems = display.upcoming
        backlogItems = display.backlog
        archiveItems = display.archive
        if let next = display.upcomingDate {
            upcomingLabel = next == Self.dayAfter(today) ? "Tomorrow" : next
        } else {
            upcomingLabel = ""
        }
        statusMessage = nil
    }

    static func dayAfter(_ date: String) -> String? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        guard let d = f.date(from: date),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: d)
        else { return nil }
        return f.string(from: next)
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
                    self?.lastWrittenData = nil
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
