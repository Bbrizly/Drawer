import Foundation
import Observation

@MainActor
@Observable
public final class PomodoroTimer {
    public enum Phase: Equatable {
        case idle, running, paused, finished
    }

    public enum Segment: Equatable {
        case focus, shortBreak, longBreak
    }

    public struct Settings: Equatable {
        public static let focusRange = 5...90
        public static let shortBreakRange = 1...30
        public static let longBreakRange = 5...60
        public static let sessionsUntilLongBreakRange = 2...8

        public static let standard = Settings(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsUntilLongBreak: 4
        )

        public var focusMinutes: Int
        public var shortBreakMinutes: Int
        public var longBreakMinutes: Int
        public var sessionsUntilLongBreak: Int

        public init(
            focusMinutes: Int,
            shortBreakMinutes: Int,
            longBreakMinutes: Int,
            sessionsUntilLongBreak: Int
        ) {
            self.focusMinutes = focusMinutes
            self.shortBreakMinutes = shortBreakMinutes
            self.longBreakMinutes = longBreakMinutes
            self.sessionsUntilLongBreak = sessionsUntilLongBreak
        }

        public var sanitized: Settings {
            Settings(
                focusMinutes: Self.clamp(focusMinutes, to: Self.focusRange),
                shortBreakMinutes: Self.clamp(shortBreakMinutes, to: Self.shortBreakRange),
                longBreakMinutes: Self.clamp(longBreakMinutes, to: Self.longBreakRange),
                sessionsUntilLongBreak: Self.clamp(
                    sessionsUntilLongBreak,
                    to: Self.sessionsUntilLongBreakRange
                )
            )
        }

        public func duration(for segment: Segment) -> TimeInterval {
            let clean = sanitized
            let minutes: Int
            switch segment {
            case .focus:
                minutes = clean.focusMinutes
            case .shortBreak:
                minutes = clean.shortBreakMinutes
            case .longBreak:
                minutes = clean.longBreakMinutes
            }
            return TimeInterval(minutes * 60)
        }

        private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var segment: Segment = .focus
    public private(set) var remaining: TimeInterval = 0
    public private(set) var completedFocusSessions = 0

    /// Fired once when a segment reaches zero.
    public var onComplete: ((Segment) -> Void)?

    private var endDate: Date?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var ticker: Timer?

    public init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    public func start(settings: Settings) {
        if phase == .finished {
            startNext(settings: settings)
        } else {
            start(segment: segment, settings: settings)
        }
    }

    public func start(segment: Segment, settings: Settings) {
        stopTicker()
        self.segment = segment
        remaining = settings.duration(for: segment)
        endDate = now().addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    public func startNext(settings: Settings) {
        start(segment: nextSegment(settings: settings), settings: settings)
    }

    public func select(segment: Segment, settings: Settings) {
        switch phase {
        case .running:
            start(segment: segment, settings: settings)
        case .idle, .paused, .finished:
            stopTicker()
            endDate = nil
            self.segment = segment
            remaining = settings.duration(for: segment)
            phase = phase == .paused ? .paused : .idle
        }
    }

    public func pause() {
        guard phase == .running, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        stopTicker()
        endDate = nil
        phase = .paused
    }

    public func resume() {
        guard phase == .paused else { return }
        endDate = now().addingTimeInterval(remaining)
        phase = .running
        startTicker()
    }

    public func reset() {
        stopTicker()
        endDate = nil
        segment = .focus
        remaining = 0
        completedFocusSessions = 0
        phase = .idle
    }

    public func nextSegment(settings: Settings) -> Segment {
        switch segment {
        case .focus:
            let cadence = settings.sanitized.sessionsUntilLongBreak
            return completedFocusSessions > 0 && completedFocusSessions % cadence == 0
                ? .longBreak
                : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    public func progress(settings: Settings) -> Double {
        let total = settings.duration(for: segment)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - (remaining / total)))
    }

    public static func format(_ t: TimeInterval) -> String {
        FocusTimer.format(t)
    }

    func tick() {
        guard phase == .running, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        if remaining == 0 {
            finishSegment()
        }
    }

    private func finishSegment() {
        stopTicker()
        endDate = nil
        remaining = 0
        if segment == .focus {
            completedFocusSessions += 1
        }
        phase = .finished
        onComplete?(segment)
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
}
