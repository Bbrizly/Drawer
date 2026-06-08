import XCTest
@testable import DrawerCore

@MainActor
final class FocusTimerTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(FocusTimer.format(0), "00:00")
        XCTAssertEqual(FocusTimer.format(59), "00:59")
        XCTAssertEqual(FocusTimer.format(60), "01:00")
        XCTAssertEqual(FocusTimer.format(25 * 60), "25:00")
        XCTAssertEqual(FocusTimer.format(125 * 60), "125:00")
    }

    func testStartSetsRunningWithEndDate() {
        let timer = FocusTimer()
        timer.start(taskTitle: "deep work", minutes: 25)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.taskTitle, "deep work")
        XCTAssertEqual(timer.remaining, 25 * 60, accuracy: 1.0)
    }

    func testStartingSecondTaskReplacesFirst() {
        let timer = FocusTimer()
        timer.start(taskTitle: "first", minutes: 25)
        timer.start(taskTitle: "second", minutes: 10)
        XCTAssertEqual(timer.taskTitle, "second")
        XCTAssertEqual(timer.remaining, 10 * 60, accuracy: 1.0)
    }

    func testPauseFreezesRemainingAndResumeContinues() {
        let timer = FocusTimer()
        timer.start(taskTitle: "t", minutes: 25)
        timer.pause()
        XCTAssertEqual(timer.phase, .paused)
        let frozen = timer.remaining
        timer.resume()
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining, frozen, accuracy: 1.0)
    }

    func testReset() {
        let timer = FocusTimer()
        timer.start(taskTitle: "t", minutes: 25)
        timer.reset()
        XCTAssertEqual(timer.phase, .idle)
        XCTAssertEqual(timer.remaining, 0)
        XCTAssertEqual(timer.taskTitle, "")
    }

    func testCompletionFiresCallback() {
        let timer = FocusTimer()
        let exp = expectation(description: "completed")
        timer.onComplete = { title in
            XCTAssertEqual(title, "quick")
            exp.fulfill()
        }
        timer.start(taskTitle: "quick", seconds: 1) // test-only seconds variant
        wait(for: [exp], timeout: 3.0)
        XCTAssertEqual(timer.phase, .idle)
    }
}
