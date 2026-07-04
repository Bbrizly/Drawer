import XCTest
@testable import DrawerCore

@MainActor
final class PomodoroTimerTests: XCTestCase {
    func testStandardSettingsUseClassicPomodoroCadence() {
        let settings = PomodoroTimer.Settings.standard

        XCTAssertEqual(settings.focusMinutes, 25)
        XCTAssertEqual(settings.shortBreakMinutes, 5)
        XCTAssertEqual(settings.longBreakMinutes, 15)
        XCTAssertEqual(settings.sessionsUntilLongBreak, 4)
        XCTAssertEqual(settings.duration(for: .focus), 25 * 60)
        XCTAssertEqual(settings.duration(for: .shortBreak), 5 * 60)
        XCTAssertEqual(settings.duration(for: .longBreak), 15 * 60)
    }

    func testSettingsClampToUsableRanges() {
        let settings = PomodoroTimer.Settings(
            focusMinutes: 0,
            shortBreakMinutes: 90,
            longBreakMinutes: 0,
            sessionsUntilLongBreak: 20
        ).sanitized

        XCTAssertEqual(settings.focusMinutes, 5)
        XCTAssertEqual(settings.shortBreakMinutes, 30)
        XCTAssertEqual(settings.longBreakMinutes, 5)
        XCTAssertEqual(settings.sessionsUntilLongBreak, 8)
    }

    func testSelectingSegmentWhileIdlePreparesThatSegmentWithoutStarting() {
        let timer = PomodoroTimer()
        let settings = PomodoroTimer.Settings.standard

        timer.select(segment: .shortBreak, settings: settings)

        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.segment, .shortBreak)
        XCTAssertEqual(timer.remaining, 5 * 60, accuracy: 1.0)

        timer.start(settings: settings)

        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.segment, .shortBreak)
        XCTAssertEqual(timer.remaining, 5 * 60, accuracy: 1.0)
    }

    func testSelectingSegmentWhileRunningRestartsTheChosenSegment() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let timer = PomodoroTimer(now: { now })
        let settings = PomodoroTimer.Settings.standard

        timer.start(segment: .focus, settings: settings)
        now.addTimeInterval(10 * 60)
        timer.tick()

        timer.select(segment: .longBreak, settings: settings)

        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.segment, .longBreak)
        XCTAssertEqual(timer.remaining, 15 * 60, accuracy: 1.0)
    }

    func testFocusCompletionAdvancesToShortBreakBeforeLongBreak() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let timer = PomodoroTimer(now: { now })
        let settings = PomodoroTimer.Settings(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsUntilLongBreak: 4
        )

        for completed in 1...3 {
            timer.start(segment: .focus, settings: settings)
            now.addTimeInterval(25 * 60)
            timer.tick()

            XCTAssertEqual(timer.phase, .finished)
            XCTAssertEqual(timer.completedFocusSessions, completed)
            XCTAssertEqual(timer.nextSegment(settings: settings), .shortBreak)

            timer.startNext(settings: settings)
            XCTAssertEqual(timer.segment, .shortBreak)
            timer.startNext(settings: settings)
            XCTAssertEqual(timer.segment, .focus)
        }
    }

    func testFourthFocusCompletionAdvancesToLongBreak() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let timer = PomodoroTimer(now: { now })
        let settings = PomodoroTimer.Settings(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsUntilLongBreak: 4
        )

        for _ in 1...4 {
            timer.start(segment: .focus, settings: settings)
            now.addTimeInterval(25 * 60)
            timer.tick()
            if timer.nextSegment(settings: settings) != .longBreak {
                timer.startNext(settings: settings)
                timer.startNext(settings: settings)
            }
        }

        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.completedFocusSessions, 4)
        XCTAssertEqual(timer.nextSegment(settings: settings), .longBreak)
        timer.startNext(settings: settings)
        XCTAssertEqual(timer.segment, .longBreak)
        XCTAssertEqual(timer.remaining, 15 * 60, accuracy: 1.0)
    }
}
