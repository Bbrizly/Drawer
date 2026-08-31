import Foundation
import Observation

@MainActor
@Observable
public final class FocusTimer {
    public enum Phase: String, Equatable, Codable, Sendable {
        case idle, running, paused, finished
    }

    public private(set) var phase: Phase = .idle
    public private(set) var taskTitle: String = ""
    public private(set) var remaining: TimeInterval = 0
    public var onComplete: ((String) -> Void)?

    private var endDate: Date?
    private var ticker: Timer?
    @ObservationIgnored private var displayActive = true

    public init() {}

    /// Absolute target used for persistence and system surfaces. Running
    /// sessions are represented by a date rather than a per-second counter so
    /// suspension, sleep and process termination do not lose time.
    public var expectedEndDate: Date? { endDate }

    public func setDisplayActive(_ active: Bool) {
        guard active != displayActive else { return }
        displayActive = active
        guard phase == .running else { return }
        tick()
        if phase == .running { startTicker() }
    }

    public func start(taskTitle: String, minutes: Int) {
        start(taskTitle: taskTitle, seconds: minutes * 60)
    }

    public func start(taskTitle: String, seconds: Int) {
        stopTicker()
        self.taskTitle = taskTitle
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

    public func restoreRunning(taskTitle: String, endDate: Date) {
        stopTicker()
        self.taskTitle = taskTitle
        self.endDate = endDate
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 {
            phase = .finished
            self.endDate = nil
        } else {
            phase = .running
            startTicker()
        }
    }

    public func restorePaused(taskTitle: String, remaining: TimeInterval) {
        stopTicker()
        self.taskTitle = taskTitle
        self.remaining = max(0, remaining)
        endDate = nil
        phase = self.remaining == 0 ? .finished : .paused
    }

    public func restoreFinished(taskTitle: String) {
        stopTicker()
        self.taskTitle = taskTitle
        remaining = 0
        endDate = nil
        phase = .finished
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
            let delay = max(0.05, (endDate?.timeIntervalSinceNow ?? 0) + 0.05)
            timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.hiddenFire() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

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
            stopTicker()
            endDate = nil
            phase = .finished
            onComplete?(taskTitle)
        }
    }
}
