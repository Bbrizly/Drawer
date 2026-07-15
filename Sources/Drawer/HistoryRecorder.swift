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
