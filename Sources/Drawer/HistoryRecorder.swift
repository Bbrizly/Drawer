import Combine
import DrawerCore
import Foundation

struct HistoryDisplay: Sendable {
    let today: [TodoItem]
    let carried: [TodoItem]
    let upcoming: [TodoItem]
    let upcomingDate: String?
    let backlog: [TodoItem]
    let archive: [TodoItem]
}

/// Reconstructs and parses one snapshot at a time for the scrubber, and
/// remembers the last few so re-scrubbing over the same steps does not go back
/// to disk.
///
/// Interactive work only. The day summary reads every retained snapshot and
/// used to share this actor, so a scrub during a summary pass waited behind up
/// to five hundred reconstructions; it lives on `HistorySummaryLoader` now.
actor HistoryLoader {
    /// Small on purpose: the scrubber walks neighbours, so a handful of steps
    /// either side is all that ever gets revisited.
    static let capacity = 32

    private let store: SnapshotStore
    /// hash -> parsed display, or nil for a snapshot whose blob is gone or no
    /// longer hashes to its recorded hash.
    private var displayCache: [String: HistoryDisplay?] = [:]
    /// Oldest first. The one thing that bounds `displayCache`.
    private var order: [String] = []
    /// The display depends on which day is "today", so a day roll invalidates
    /// every parse even though the bytes are unchanged.
    private var cachedToday: String?

    init(store: SnapshotStore) { self.store = store }

    var cachedCount: Int { displayCache.count }

    func display(for record: SnapshotRecord, today: String) -> HistoryDisplay? {
        if cachedToday != today {
            cachedToday = today
            displayCache.removeAll()
            order.removeAll()
        }
        if let cached = displayCache[record.hash] {
            // A hit is a use: without this the order never moved and the cache
            // evicted by insertion age, not by least-recently-used.
            touch(record.hash)
            return cached
        }
        guard let text = markdown(for: record) else {
            insert(nil, for: record.hash)
            return nil
        }
        let parsed = TodoParser.display(sections: TodoParser.parse(text), today: today)
        let result = HistoryDisplay(
            today: parsed.today, carried: parsed.carried, upcoming: parsed.upcoming,
            upcomingDate: parsed.upcomingDate, backlog: parsed.backlog, archive: parsed.archive)
        insert(result, for: record.hash)
        return result
    }

    /// The snapshot's bytes as text, or nil if the blob is missing or fails the
    /// hash check. Never retained past the caller's use of it.
    private func markdown(for record: SnapshotRecord) -> String? {
        guard case let .available(data) = store.reconstruct(record) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Plain LRU: reading or writing a hash moves it to the end, and the front
    /// falls off once the cache is over capacity.
    private func insert(_ value: HistoryDisplay?, for hash: String) {
        displayCache[hash] = value
        touch(hash)
        while order.count > Self.capacity {
            displayCache[order.removeFirst()] = nil
        }
    }

    private func touch(_ hash: String) {
        order.removeAll { $0 == hash }
        order.append(hash)
    }
}

/// The day band's tallies: every retained snapshot reconstructed, diffed
/// against the one before it, and rolled up per day.
///
/// The work itself runs on a detached task, not on this actor, so the actor is
/// free between requests. That is what makes a newer request able to supersede
/// an older one: the older one comes back to find its generation stale and
/// returns nil rather than publishing a summary of records that have since
/// changed.
actor HistorySummaryLoader {
    private let store: SnapshotStore
    private var generation = 0
    private var cachedRecords: [SnapshotRecord]?
    private var cached: [DayTally] = []
    /// The pass currently running, and what it is a pass over. The scrubber has
    /// an inline and a full flavour over one recorder, so the same question
    /// arrives twice; both wait on the one pass instead of starting two.
    private var running: Task<[DayTally], Never>?
    private var runningRecords: [SnapshotRecord]?

    init(store: SnapshotStore) { self.store = store }

    /// The tallies for `records`, or nil when a newer request came in while
    /// this one was running.
    func dailySummary(for records: [SnapshotRecord]) async -> [DayTally]? {
        if cachedRecords == records { return cached }
        if runningRecords == records, let running {
            let mine = generation
            let tallies = await running.value
            return mine == generation ? tallies : nil
        }
        // A pass over records nobody is waiting for any more is wasted work,
        // and captures can arrive faster than a pass takes.
        running?.cancel()
        generation += 1
        let mine = generation
        let store = store
        let pass = Task.detached(priority: .utility) {
            HistorySummaryLoader.build(records: records, store: store)
        }
        running = pass
        runningRecords = records
        let tallies = await pass.value
        guard mine == generation else { return nil }
        running = nil
        runningRecords = nil
        cached = tallies
        cachedRecords = records
        return tallies
    }

    /// Walks the snapshots oldest first, feeding each one to the diff and
    /// letting it go before reading the next. Nothing is cached along the way:
    /// the summary touches every retained snapshot, and holding that set is the
    /// leak this replaced.
    private static func build(
        records: [SnapshotRecord], store: SnapshotStore
    ) -> [DayTally] {
        var accumulator = HistoryTimelineAccumulator()
        for record in records.sorted(by: { $0.ts < $1.ts }) {
            if Task.isCancelled { break }
            guard case let .available(data) = store.reconstruct(record),
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            accumulator.add(ts: record.ts, markdown: text)
        }
        return HistoryTimelineBuilder.dailySummary(accumulator.finish())
    }
}

/// Captures a debounced history of Drawer.md while the app runs. Driven by the
/// existing FileWatcher: a launch capture anchors "now", then each change arms a
/// quiet-period debounce so one logical edit yields one clean snapshot. Never
/// blocks a write. Capture is always after the fact, off the write path.
@MainActor
final class HistoryRecorder: ObservableObject {
    @Published private(set) var records: [SnapshotRecord] = []

    private let store: SnapshotStore
    private var fileURL: URL
    private var watcher: FileWatcher
    private var debouncer = QuietPeriodDebouncer(quietInterval: 3)
    private var pollTimer: Timer?
    private let retention = 500
    private var running = false
    private let loader: HistoryLoader
    private let summaryLoader: HistorySummaryLoader

    init(store: SnapshotStore, fileURL: URL) {
        self.store = store
        self.loader = HistoryLoader(store: store)
        self.summaryLoader = HistorySummaryLoader(store: store)
        self.fileURL = fileURL
        watcher = FileWatcher(
            directory: fileURL.deletingLastPathComponent(), pollFile: fileURL)
        records = store.readRange()
        watcher.onChange = { [weak self] in self?.fileChanged() }
    }

    func start() {
        guard !running else { return }
        running = true
        // Watch first, then capture, so a write landing during the launch
        // snapshot is still observed rather than missed until the next change.
        watcher.start()
        capture()
    }

    /// Points at a different drawer file (Settings changed the path). Rebuilds
    /// the watcher so history stops following the old file.
    func repoint(to newFileURL: URL) {
        let wasRunning = running
        stop()
        fileURL = newFileURL
        watcher = FileWatcher(
            directory: newFileURL.deletingLastPathComponent(), pollFile: newFileURL)
        watcher.onChange = { [weak self] in self?.fileChanged() }
        if wasRunning { start() }
    }

    func stop() {
        guard running else { return }
        running = false
        watcher.stop()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func display(for record: SnapshotRecord, today: String) async -> HistoryDisplay? {
        await loader.display(for: record, today: today)
    }

    /// nil when a newer summary request overtook this one.
    func dailySummary(for records: [SnapshotRecord]) async -> [DayTally]? {
        await summaryLoader.dailySummary(for: records)
    }

    private func fileChanged() {
        debouncer.change(at: Date())
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard debouncer.dueActions(at: Date()) else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        capture()
    }

    private func capture() {
        // Disk read, SHA-256, and the blob/index writes all run off the main
        // actor so a capture never touches the frame the hotkey slide needs.
        // SnapshotStore is a Sendable value type, so it hands across cleanly.
        let url = fileURL
        let store = store
        let retention = retention
        Task.detached(priority: .utility) { [weak self] in
            guard let bytes = try? Data(contentsOf: url) else { return }
            guard case .appended = (try? store.append(bytes: bytes, ts: Date())) else { return }
            var range = store.readRange()
            // Prune rewrites the whole index and lists the blob dir; skip it
            // until retention actually overflows.
            if range.count > retention, (try? store.prune(keepLast: retention)) != nil {
                range = store.readRange()
            }
            let snapshot = range
            await self?.publish(snapshot)
        }
    }

    private func publish(_ snapshot: [SnapshotRecord]) {
        records = snapshot
    }
}
