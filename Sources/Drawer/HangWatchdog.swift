#if !APPSTORE
import Foundation

/// Catches a frozen main thread and writes a stack sample to the home folder,
/// so an intermittent hang leaves evidence without anyone having to run
/// `sample` by hand. Dev builds only: compiled out of the App Store flavor.
///
/// A background timer pings the main thread once a second. When the main thread
/// has not answered a ping for `stallSeconds` it is wedged, so we shell out to
/// `/usr/bin/sample`, which reads the stuck thread's stack from outside the
/// process. One capture per stall, named by time, so a real freeze drops a
/// `drawer-hang-<epoch>.txt` naming the exact frame the main thread is stuck in.
final class HangWatchdog {
    private let queue = DispatchQueue(label: "com.bbrizly.drawer.hang-watchdog")
    private let stallSeconds: TimeInterval
    private var timer: DispatchSourceTimer?
    // Touched only on `queue`.
    private var waitingSince: Date?
    private var capturedThisStall = false

    init(stallSeconds: TimeInterval = 5) {
        self.stallSeconds = stallSeconds
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        // A ping is still outstanding: main has not run our block yet. If it
        // has been stuck past the threshold, grab one sample and wait for
        // recovery before arming the next.
        if let since = waitingSince {
            if !capturedThisStall, Date().timeIntervalSince(since) >= stallSeconds {
                capturedThisStall = true
                capture(stalledFor: Date().timeIntervalSince(since))
            }
            return
        }
        // Send a fresh ping. A healthy main thread clears it within the second;
        // a wedged one never does, so `waitingSince` keeps aging.
        waitingSince = Date()
        capturedThisStall = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue.async { self.waitingSince = nil }
        }
    }

    private func capture(stalledFor seconds: TimeInterval) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let stamp = Int(Date().timeIntervalSince1970)
        let out = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("drawer-hang-\(stamp).txt").path
        NSLog("Drawer main thread stalled %.1fs, sampling to %@", seconds, out)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        task.arguments = [String(pid), "3", "-file", out]
        try? task.run()
    }
}
#endif
