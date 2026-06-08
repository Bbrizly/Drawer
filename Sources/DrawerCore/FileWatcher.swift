import Foundation

/// Watches a directory (not the file) so atomic-replace saves from
/// Obsidian, iCloud, or an editor don't orphan the watch. Debounces bursts.
///
/// If the directory can't be opened yet (e.g. the app launched at login
/// before iCloud Drive mounted), it retries until it can attach, then
/// fires `onChange` once so the consumer reloads.
///
/// `start()`/`stop()` must be called from the main thread.
public final class FileWatcher {
    private let dirURL: URL
    private let retryInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.bassam.drawer.watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?

    /// Called on the main queue, debounced 200ms.
    public var onChange: (() -> Void)?

    public init(directory: URL, retryInterval: TimeInterval = 5) {
        self.dirURL = directory
        self.retryInterval = retryInterval
    }

    public func start() {
        stop()
        attach(notifyOnAttach: false)
    }

    public func stop() {
        retryWork?.cancel()
        retryWork = nil
        source?.cancel()
        source = nil
    }

    private func attach(notifyOnAttach: Bool) {
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.scheduleNotify() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        if notifyOnAttach {
            // The directory just became available; let the consumer reload.
            onChange?()
        }
    }

    private func scheduleRetry() {
        let work = DispatchWorkItem { [weak self] in
            self?.attach(notifyOnAttach: true)
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryInterval, execute: work)
    }

    private func scheduleNotify() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange?() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    deinit {
        retryWork?.cancel()
        source?.cancel()
    }
}
