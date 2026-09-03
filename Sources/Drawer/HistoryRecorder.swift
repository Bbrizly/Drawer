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

actor HistoryLoader {
    private let store: SnapshotStore
    private var dataCache: [String: Data] = [:]
    private var displayCache: [String: HistoryDisplay?] = [:]
    private var order: [String] = []
    private var summaryRecords: [SnapshotRecord]?
    private var summary: [DayTally] = []
    private let capacity = 64

    init(store: SnapshotStore) { self.store = store }

    func display(for record: SnapshotRecord, today: String) -> HistoryDisplay? {
        if let cached = displayCache[record.hash] { return cached }
        guard let data = bytes(for: record), let text = String(data: data, encoding: .utf8) else {
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

    func dailySummary(for records: [SnapshotRecord]) -> [DayTally] {
        if summaryRecords == records { return summary }
        let snapshots: [TimelineSnapshot] = records.compactMap { record in
            guard let data = bytes(for: record), let text = String(data: data, encoding: .utf8) else { return nil }
            return TimelineSnapshot(ts: record.ts, markdown: text)
        }
        summary = HistoryTimelineBuilder.dailySummary(
            HistoryTimelineBuilder.build(snapshots: snapshots))
        summaryRecords = records
        return summary
    }

    private func bytes(for record: SnapshotRecord) -> Data? {
        if let data = dataCache[record.hash] { return data }
        guard case let .available(data) = store.reconstruct(record) else { return nil }
        dataCache[record.hash] = data
        return data
    }

    private func insert(_ value: HistoryDisplay?, for hash: String) {
        displayCache[hash] = value
        order.removeAll { $0 == hash }
        order.append(hash)
        while order.count > capacity {
            let old = order.removeFirst()
            displayCache[old] = nil
            dataCache[old] = nil
        }
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

    init(store: SnapshotStore, fileURL: URL) {
        self.store = store
        self.loader = HistoryLoader(store: store)
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

    func dailySummary(for records: [SnapshotRecord]) async -> [DayTally] {
        await loader.dailySummary(for: records)
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
