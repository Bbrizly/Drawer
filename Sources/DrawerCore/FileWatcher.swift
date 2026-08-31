import Foundation

#if os(macOS)
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
    private let queue = DispatchQueue(label: "com.bbrizly.drawer.watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private var pollStamp: (Date, Int)?

    /// Called on the main queue, debounced 200ms.
    public var onChange: (() -> Void)?

    /// `pollFile` is the file the caller actually cares about inside
    /// `directory`. When the directory itself can't be opened (the sandboxed
    /// App Store build's user-selected grant covers the picked file but not
    /// its parent) changes to that file are detected by polling its
    /// modification date instead of vnode events.
    public init(directory: URL, retryInterval: TimeInterval = 5, pollFile: URL? = nil) {
        self.dirURL = directory
        self.retryInterval = retryInterval
        self.pollFile = pollFile
    }

    private let pollFile: URL?

    public func start() {
        stop()
        attach(notifyOnAttach: false)
    }

    public func stop() {
        retryWork?.cancel()
        retryWork = nil
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        stopPolling()
    }

    private func attach(notifyOnAttach: Bool) {
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRetry()
            startPollingIfPossible()
            return
        }
        stopPolling()
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
        retryWork?.cancel()
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

    // MARK: polling fallback

    // 2s mtime+size poll while the directory is unopenable; the vnode source
    // takes back over the moment a retry attach succeeds.
    private func startPollingIfPossible() {
        guard let file = pollFile, pollTimer == nil else { return }
        pollStamp = Self.stamp(of: file)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Self.stamp(of: file)
            if now?.0 != self.pollStamp?.0 || now?.1 != self.pollStamp?.1 {
                self.pollStamp = now
                self.scheduleNotify()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private static func stamp(of url: URL) -> (Date, Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return (attrs[.modificationDate] as? Date ?? .distantPast,
                attrs[.size] as? Int ?? 0)
    }

    deinit {
        pending?.cancel()
        retryWork?.cancel()
        source?.cancel()
        pollTimer?.cancel()
    }
}
#else
/// Portable fallback used by the shared core on platforms without the macOS
/// vnode watcher. The iOS app itself uses `NSFilePresenter` for its selected
/// Drawer document; this poller keeps `TodoStore` and `ParkingLotStore`
/// functional and, critically, keeps `DrawerCore` a genuinely portable target.
///
/// `start()`/`stop()` should be called from the main thread, matching the
/// macOS implementation. Changes are delivered on the main queue.
public final class FileWatcher {
    private let pollFile: URL?
    private let queue = DispatchQueue(label: "com.bbrizly.drawer.watcher.portable", qos: .utility)
    private var pollTimer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var pollStamp: (Date, Int)?

    public var onChange: (() -> Void)?

    public init(directory: URL, retryInterval: TimeInterval = 5, pollFile: URL? = nil) {
        // Keep the same API as the macOS implementation. Directory and retry
        // interval are intentionally unused here because iOS file access is
        // scoped to the selected document rather than its parent directory.
        _ = directory
        _ = retryInterval
        self.pollFile = pollFile
    }

    public func start() {
        stop()
        guard let pollFile else { return }
        pollStamp = Self.stamp(of: pollFile)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let next = Self.stamp(of: pollFile)
            if next?.0 != self.pollStamp?.0 || next?.1 != self.pollStamp?.1 {
                self.pollStamp = next
                self.scheduleNotify()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        pollTimer?.cancel()
        pollTimer = nil
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

    private static func stamp(of url: URL) -> (Date, Int)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return (attrs[.modificationDate] as? Date ?? .distantPast,
                attrs[.size] as? Int ?? 0)
    }

    deinit {
        pending?.cancel()
        pollTimer?.cancel()
    }
}
#endif
