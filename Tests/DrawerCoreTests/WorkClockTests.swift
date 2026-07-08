import XCTest
@testable import DrawerCore

/// A clock we can advance by hand. Reference type so a non-escaping closure can
/// read the latest value.
private final class FakeClock: @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 1_000_000)   // a safe mid-day baseline
    func advance(_ seconds: TimeInterval) { t = t.addingTimeInterval(seconds) }
}

@MainActor
final class WorkClockTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "work-clock-test-\(UUID().uuidString)")!
    }

    private func makeClock(
        _ box: LogBox, _ clk: FakeClock, _ defaults: UserDefaults
    ) -> WorkClock {
        WorkClock(log: makeMemoryLog(box), now: { clk.t }, defaults: defaults)
    }

    func testTrackThenPauseLogsOneSession() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(100)
        wc.pause()
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.taskTitle, "A")
        XCTAssertEqual(all.first?.seconds ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(wc.phase, .paused)
        XCTAssertEqual(wc.activeTaskTotal, 100, accuracy: 0.001)
    }

    func testSwitchingTaskClosesPreviousAndOpensNew() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(50)
        wc.track(taskID: "id2", title: "B")        // closes A, opens B
        XCTAssertEqual(wc.activeTaskTitle, "B")
        XCTAssertEqual(makeMemoryLog(box).all().map(\.taskTitle), ["A"])
        clk.advance(30)
        wc.pause()
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.last?.taskTitle, "B")
        XCTAssertEqual(all.last?.seconds ?? 0, 30, accuracy: 0.001)
    }

    func testPauseResumeOpensNewSegmentAndAccumulates() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(40)
        wc.pause()
        clk.advance(5)                              // idle while paused
        wc.resume()
        clk.advance(10)
        wc.pause()
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.map(\.seconds).reduce(0, +), 50, accuracy: 0.001)
        XCTAssertEqual(wc.activeTaskTotal, 50, accuracy: 0.001)
    }

    func testCompletingTrackedTaskStopsClock() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(20)
        wc.taskCompleted(id: "id1", title: "A")
        XCTAssertEqual(wc.phase, .paused)
        XCTAssertEqual(makeMemoryLog(box).all().count, 1)
    }

    func testCompletingOtherTaskDoesNotStopClock() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        wc.taskCompleted(id: "id9", title: "Z")
        XCTAssertEqual(wc.phase, .running)
    }

    func testRestoreResumesFreshSegment() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc1 = makeClock(box, clk, defaults)
        wc1.enter()
        wc1.track(taskID: "id1", title: "A")        // persists, segment open
        clk.advance(30)                             // within grace, simulate relaunch
        let wc2 = makeClock(box, clk, defaults)
        wc2.restore()
        XCTAssertEqual(wc2.phase, .running)
        XCTAssertEqual(wc2.activeTaskTitle, "A")
        clk.advance(10)
        wc2.pause()
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.seconds ?? 0, 40, accuracy: 0.001)
    }

    func testRestoreDropsStaleSegment() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc1 = makeClock(box, clk, defaults)
        wc1.enter()
        wc1.track(taskID: "id1", title: "A")
        clk.advance(WorkClock.resumeGraceSeconds + 60)   // beyond grace
        let wc2 = makeClock(box, clk, defaults)
        wc2.restore()
        XCTAssertEqual(wc2.phase, .paused)
        XCTAssertNotNil(wc2.statusMessage)
        XCTAssertEqual(makeMemoryLog(box).all().count, 0)   // nothing invented
        XCTAssertEqual(wc2.activeTaskTitle, "A")            // task retained for resume
    }

    func testSplitClosesAndReopens() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(60)
        wc.splitAtMidnight()
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.seconds ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(wc.phase, .running)
        XCTAssertEqual(wc.activeTaskTitle, "A")
    }

    func testEndReturnsSummaryAndResets() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(120)
        let today = dayStringForTest(clk.t)
        let summary = wc.end(today: today)
        XCTAssertEqual(wc.phase, .off)
        XCTAssertEqual(summary.total, 120, accuracy: 0.001)
        XCTAssertEqual(summary.rows.first?.taskTitle, "A")
        XCTAssertEqual(wc.activeTaskID, nil)
    }

    func testEditSummaryRewritesTotal() {
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        let wc = makeClock(box, clk, defaults)
        wc.enter()
        wc.track(taskID: "id1", title: "A")
        clk.advance(100)
        let day = dayStringForTest(clk.t)
        wc.end(today: day)
        let edited = wc.editSummary(title: "A", seconds: 600, on: day)
        XCTAssertEqual(edited.total, 600, accuracy: 0.001)
        XCTAssertEqual(edited.rows.first?.taskTitle, "A")
        // And removing it leaves an empty summary.
        let cleared = wc.editSummary(title: "A", seconds: 0, on: day)
        XCTAssertTrue(cleared.rows.isEmpty)
    }

    func testDayKeyFormatterIsPOSIXGregorian() {
        // WorkSessionLog writes Gregorian POSIX day keys. WorkClock must match, or
        // total(forTitle:on:) never finds previously logged time on a non-Gregorian
        // system calendar (a Buddhist locale would otherwise key today as 2569).
        let box = LogBox(); let clk = FakeClock(); let defaults = makeDefaults()
        var cal = Calendar(identifier: .buddhist)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wc = WorkClock(
            log: makeMemoryLog(box), now: { clk.t }, calendar: cal, defaults: defaults)
        XCTAssertEqual(wc.dayFormatter.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(wc.dayFormatter.string(from: clk.t), "1970-01-12")   // not 2513
    }

    private func dayStringForTest(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = Calendar.current.timeZone
        return f.string(from: date)
    }
}
