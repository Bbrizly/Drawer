import Combine
import Foundation

/// The drawer file as the UI sees it. Owns the published sections, the watcher
/// and the day-change observers; every read, write and parse belongs to
/// `TodoFileWorker` and happens off this actor.
///
/// Operations are chained rather than fired independently, so a burst of
/// toggles hits the file in the order the user made them, and a slow reload
/// started before an edit can never publish over the edit's result.
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
    private let worker: TodoFileWorker
    /// Bumped by `updateFileURL`. Work already in flight against the old file
    /// finishes harmlessly instead of publishing tasks from a file we no longer
    /// show.
    private var fileToken = 0
    /// The tail of the file chain, off the main actor. Each new operation
    /// awaits this one, so transactions reach the disk in the order they were
    /// asked for. Nothing in it touches the main actor, which is what lets
    /// teardown block the main thread until it drains.
    private var fileChain: Task<TodoFileOutcome, Never>?
    /// The tail of the publish chain, on the main actor. Each publish awaits
    /// its own file operation and the publish before it, so the UI sees results
    /// in the same order.
    private var publishChain: Task<Void, Never>?
    /// Operations accepted and not yet published.
    private var pending = 0
    /// Deletes queued but not yet published. Every command captured against the
    /// display sits one row higher for each of these, so its position has to be
    /// shifted down before it runs. Each entry is dropped when its own delete
    /// publishes, because from then on the display already counts without it.
    private var pendingDeletes: [(section: String, ordinal: Int)] = []
    /// The position numbering the visible items belong to. Commands carry it so
    /// the worker can tell them whether it still holds.
    private var displayEpoch = 0
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
        self.worker = TodoFileWorker(
            fileURL: fileURL, readData: readData, writeData: writeData)
    }

    /// Switches the backing file at runtime (settings change). Rewires the
    /// directory watcher and reloads immediately.
    public func updateFileURL(_ url: URL) {
        guard url != fileURL else { return }
        watcher.stop()
        fileURL = url
        fileToken += 1
        watcher = FileWatcher(directory: url.deletingLastPathComponent(), pollFile: url)
        watcher.onChange = { [weak self] in self?.reload() }
        watcher.start()
        let today = todayProvider()
        enqueue { worker in
            // Two calls, but nothing else can reach the worker between them:
            // the next queued operation is waiting on this whole closure.
            await worker.setFileURL(url)
            return await worker.reload(today: today)
        }
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

    /// Waits until every queued file operation has finished and been applied.
    /// The UI never needs this: it just gets the publish when it lands. Tests
    /// do.
    public func settle() async {
        await publishChain?.value
    }

    /// Blocks the caller until every file operation already accepted has been
    /// written. For teardown: `applicationWillTerminate` runs on the main
    /// thread and the process dies the moment it returns, so a toggle queued a
    /// keystroke earlier has to land first. Blocking here is safe because the
    /// write chain never touches the main actor. The publishes that would
    /// follow are abandoned along with the UI.
    @discardableResult
    public func flushPendingWrites(timeout: TimeInterval = 5) -> Bool {
        guard let chain = fileChain else { return true }
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            _ = await chain.value
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            // A stalled volume. Quitting anyway beats hanging the quit, but say
            // so: this is the one path where an accepted edit is still lost.
            NSLog("Drawer: gave up waiting for queued task writes after %.0fs", timeout)
            return false
        }
        return true
    }

    public func reload() {
        let today = todayProvider()
        enqueue { await $0.reload(today: today) }
    }

    public func toggle(_ item: TodoItem) {
        let target = target(for: item)
        mutate { data, ours in
            try TodoWriteback.toggle(target: target.trusting(ours), in: data)
        }
    }

    public func delete(_ item: TodoItem) {
        let target = target(for: item)
        let shifting = target.ordinal != nil
        if let ordinal = target.ordinal {
            pendingDeletes.append((item.sectionDate, ordinal))
        }
        mutate(retiringADelete: shifting) { data, ours in
            try TodoWriteback.delete(target: target.trusting(ours), in: data)
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
        let target = target(for: item)
        mutate { data, ours in
            try TodoWriteback.setInProgress(
                target: target.trusting(ours), inProgress: inProgress, in: data)
        }
    }

    public func setNote(_ item: TodoItem, _ note: String) {
        let target = target(for: item)
        mutate { data, ours in
            try TodoWriteback.setNote(target: target.trusting(ours), note: note, in: data)
        }
    }

    /// Commits a day plan through the shared PlanWriter (the same path the MCP
    /// server uses). Throws PlanWriter's validation errors so the caller can
    /// surface a rejection instead of silently doing nothing.
    public func writeDayPlan(date: String, entries: [PlanEntry], replace: Bool) async throws {
        let today = todayProvider()
        let failure = Box<Error>()
        let task = enqueue { worker in
            do {
                // A plan replace rewrites whole day sections, so no command
                // queued behind it may trust the position it captured.
                return .display(try await worker.commit(
                    today: today, readingMissingAsEmpty: true, preservesOrdinals: false
                ) { data, _ in  // a plan replace never trusts a captured position
                    try PlanWriter.write(date: date, entries: entries, replace: replace, in: data)
                })
            } catch {
                failure.value = error
                return .unchanged
            }
        }
        await task.value
        if let error = failure.value { throw error }
    }

    public func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Capture today once: the CAS transform may run twice, and it must not
        // roll to a new day between the two passes.
        let today = todayProvider()
        write(readingMissingAsEmpty: true) { data, _ in
            try TodoWriteback.append(title: trimmed, today: today, in: data)
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
        write(readingMissingAsEmpty: true) { data, _ in
            try TodoWriteback.insert(
                line: line, intoSectionKey: key, displayHeading: displayHeading, in: data)
        }
    }

    /// Renames a task in place, writing the new title back to its line.
    public func rename(_ item: TodoItem, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        let target = target(for: item)
        mutate { data, ours in
            try TodoWriteback.rename(target: target.trusting(ours), to: trimmed, in: data)
        }
    }

    // MARK: pipeline

    /// Queues one file transaction behind whatever is already queued and
    /// publishes its result, unless the file has been switched out from under
    /// it in the meantime.
    @discardableResult
    private func enqueue(
        retiringADelete: Bool = false,
        _ operation: @escaping @Sendable (TodoFileWorker) async -> TodoFileOutcome
    ) -> Task<Void, Never> {
        let worker = worker
        let previousFile = fileChain
        let file = Task.detached(priority: .userInitiated) { () -> TodoFileOutcome in
            _ = await previousFile?.value
            return await operation(worker)
        }
        fileChain = file

        let previousPublish = publishChain
        let token = fileToken
        let publish = Task { @MainActor [weak self] in
            await previousPublish?.value
            let outcome = await file.value
            guard let self else { return }
            defer { self.finished(retiringADelete: retiringADelete) }
            guard self.fileToken == token else { return }
            self.publish(outcome)
        }
        publishChain = publish
        pending += 1
        return publish
    }

    /// One operation left the queue. A delete's own publish is the moment the
    /// visible rows renumber, so its shift stops applying right there rather
    /// than when the whole queue happens to drain. Deletes publish in the order
    /// they were queued, so the oldest entry is always this one's.
    private func finished(retiringADelete: Bool) {
        if retiringADelete, !pendingDeletes.isEmpty { pendingDeletes.removeFirst() }
        pending -= 1
        guard pending == 0 else { return }
        pendingDeletes.removeAll()
        fileChain = nil
        publishChain = nil
    }

    /// The task a command means, in a form that survives the commands queued
    /// ahead of it: where the row sat when the user acted, shifted down by any
    /// delete still queued in front of it.
    private func target(for item: TodoItem) -> TodoTarget {
        var ordinal = item.ordinal
        for deleted in pendingDeletes
        where deleted.section == item.sectionDate && deleted.ordinal < ordinal {
            ordinal -= 1
        }
        return TodoTarget(
            sectionKey: item.sectionDate, rawLine: item.rawLine,
            ordinal: ordinal, occurrence: item.occurrence)
    }

    private func mutate(
        retiringADelete: Bool = false,
        _ transform: @escaping @Sendable (Data, Bool) throws -> Data
    ) {
        let today = todayProvider()
        let epoch = displayEpoch
        enqueue(retiringADelete: retiringADelete) {
            await $0.mutate(today: today, epoch: epoch, transform)
        }
    }

    private func write(
        readingMissingAsEmpty: Bool,
        _ transform: @escaping @Sendable (Data, Bool) throws -> Data
    ) {
        let today = todayProvider()
        enqueue {
            await $0.write(
                today: today, readingMissingAsEmpty: readingMissingAsEmpty, transform)
        }
    }

    private func publish(_ outcome: TodoFileOutcome) {
        switch outcome {
        case .unchanged:
            break
        case let .display(snapshot):
            apply(snapshot)
        case .missingFile:
            clearSections()
            statusMessage = "No drawer file yet"
        case .unreadable:
            clearSections()
            statusMessage = "Could not read drawer file"
        case .notUTF8:
            statusMessage = "File is not UTF-8"
        case .writeFailed:
            statusMessage = "Could not save drawer file"
        }
    }

    private func clearSections() {
        todayItems = []
        carriedItems = []
        upcomingItems = []
        upcomingLabel = ""
        backlogItems = []
        archiveItems = []
    }

    private func apply(_ snapshot: TodoDisplaySnapshot) {
        displayEpoch = snapshot.epoch
        // Publish only what actually changed. An edit usually touches one
        // section; the other five publishes would re-evaluate every
        // subscriber's body for nothing. The compares are cheap value
        // equality on the visible items.
        if todayItems != snapshot.today { todayItems = snapshot.today }
        if carriedItems != snapshot.carried { carriedItems = snapshot.carried }
        if upcomingItems != snapshot.upcoming { upcomingItems = snapshot.upcoming }
        if backlogItems != snapshot.backlog { backlogItems = snapshot.backlog }
        if archiveItems != snapshot.archive { archiveItems = snapshot.archive }
        let label: String
        if let next = snapshot.upcomingDate {
            label = next == Self.dayAfter(todayProvider()) ? "Tomorrow" : next
        } else {
            label = ""
        }
        if upcomingLabel != label { upcomingLabel = label }
        if statusMessage != nil { statusMessage = nil }
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
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let today = self.todayProvider()
                    self.enqueue { worker in
                        // Both caches must go: "today" changed, so identical
                        // bytes no longer mean an identical display.
                        await worker.forgetSuppression()
                        return await worker.reload(today: today)
                    }
                }
            }
        }
    }
}

/// A one-slot handoff for a value produced inside a queued operation and read
/// back once that operation has finished. The pipeline puts a happens-before
/// edge between the write and the read, so there is nothing to lock.
private final class Box<T>: @unchecked Sendable {
    var value: T?
}
