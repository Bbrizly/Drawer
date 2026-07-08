import Foundation
import Observation

@MainActor
@Observable
public final class FocusTimer {
    /// `finished` is the alarm state: the countdown hit zero and the timer
    /// waits, ringing, until `reset()` dismisses it. It never returns to idle
    /// on its own so the completion cannot be missed.
    public enum Phase: Equatable {
        case idle, running, paused, finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var taskTitle: String = ""
    public private(set) var remaining: TimeInterval = 0

    /// Fired once when the countdown hits zero, with the task title.
    public var onComplete: ((String) -> Void)?

    private var endDate: Date?
    private var ticker: Timer?
    /// False while the panel is hidden. The 0.5s display tick is pure waste
    /// with no one looking, so hiding swaps it for a one-shot at the end date
    /// (completion still fires on time), and showing brings the tick back.
    @ObservationIgnored private var displayActive = true

    public init() {}

    /// Call when the panel shows (true) or hides (false).
    public func setDisplayActive(_ active: Bool) {
        guard active != displayActive else { return }
        displayActive = active
        guard phase == .running else { return }
        tick() // refresh `remaining` before the mode switch
        if phase == .running { startTicker() }
    }

    public func start(taskTitle: String, minutes: Int) {
        start(taskTitle: taskTitle, seconds: minutes * 60)
    }

    public func start(taskTitle: String, seconds: Int) {
        stopTicker()
        self.taskTitle = taskTitle
        // Absolute end date: accurate across sleep/wake and run-loop stalls.
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        remaining = TimeInterval(seconds)
        phase = .running
        startTicker()
    }

    public func pause() {
        guard phase == .running, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        stopTicker()
        endDate = nil
        phase = .paused
    }

    public func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    public func reset() {
        stopTicker()
        endDate = nil
        remaining = 0
        taskTitle = ""
        phase = .idle
    }

    public static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func startTicker() {
        stopTicker()
        let timer: Timer
        if displayActive {
            timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else {
            // Hidden: one wakeup just past zero instead of two per second.
            let delay = max(0.05, (endDate?.timeIntervalSinceNow ?? 0) + 0.05)
            timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.hiddenFire() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// The hidden one-shot landed. Normally the tick finishes the timer; if a
    /// backward clock jump left time on the clock, re-arm for the new end.
    private func hiddenFire() {
        tick()
        if phase == .running { startTicker() }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining == 0 {
            // Hold in `finished` (keeping the title for the alarm card) instead
            // of resetting, so the UI can demand a dismissal.
            stopTicker()
            endDate = nil
            phase = .finished
            onComplete?(taskTitle)
        }
    }
}
