import Combine
import Foundation

@MainActor
public final class FocusTimer: ObservableObject {
    public enum Phase: Equatable {
        case idle, running, paused
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var taskTitle: String = ""
    @Published public private(set) var remaining: TimeInterval = 0

    /// Fired once when the countdown hits zero, with the task title.
    public var onComplete: ((String) -> Void)?

    private var endDate: Date?
    private var ticker: Timer?

    public init() {}

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
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining == 0 {
            let finished = taskTitle
            reset()
            onComplete?(finished)
        }
    }
}
