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
    private var fileURL: URL
    private var watcher: FileWatcher
    private var debouncer = QuietPeriodDebouncer(quietInterval: 3)
    private var pollTimer: Timer?
    private let retention = 500
    private var running = false

    init(store: SnapshotStore, fileURL: URL) {
        self.store = store
        self.fileURL = fileURL
        watcher = FileWatcher(directory: fileURL.deletingLastPathComponent())
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
        watcher = FileWatcher(directory: newFileURL.deletingLastPathComponent())
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
