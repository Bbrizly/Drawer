import Combine
import DrawerCore
import Foundation

/// Captures a debounced history of Drawer.md while the app runs. Driven by the
/// existing FileWatcher: a launch capture anchors "now", then each change arms a
/// quiet-period debounce so one logical edit yields one clean snapshot. Never
/// blocks a write — capture is always after the fact, off the write path.
@MainActor
final class HistoryRecorder: ObservableObject {
    @Published private(set) var records: [SnapshotRecord] = []

    private let store: SnapshotStore
    private let fileURL: URL
    private let watcher: FileWatcher
    private var debouncer = QuietPeriodDebouncer(quietInterval: 3)
    private var pollTimer: Timer?
    private let retention = 500
    private var running = false

    init(store: SnapshotStore, fileURL: URL) {
        self.store = store
        self.fileURL = fileURL
        watcher = FileWatcher(directory: fileURL.deletingLastPathComponent())
        watcher.onChange = { [weak self] in self?.fileChanged() }
        records = store.readRange()
    }

    func start() {
        guard !running else { return }
        running = true
        capture()          // anchor the session with a "now" snapshot
        watcher.start()
    }

    func stop() {
        guard running else { return }
        running = false
        watcher.stop()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func reconstruct(_ record: SnapshotRecord) -> SnapshotReadResult {
        store.reconstruct(record)
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
        guard let bytes = try? Data(contentsOf: fileURL) else { return }
        guard case .appended = (try? store.append(bytes: bytes, ts: Date())) else { return }
        try? store.prune(keepLast: retention)
        records = store.readRange()
    }
}
