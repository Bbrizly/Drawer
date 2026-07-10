import XCTest
@testable import DrawerCore

@MainActor
final class WorkHeaderStateTests: XCTestCase {
    // Hand-tracking a task: the pill is "Working".
    func testRunningIsWorking() {
        XCTAssertEqual(workHeaderState(phase: .running, hasTask: true, observing: false), .working)
    }

    // A hand-tracked task paused by hand stays "Paused", watcher or not.
    func testPausedTaskIsPaused() {
        XCTAssertEqual(workHeaderState(phase: .paused, hasTask: true, observing: false), .paused)
        XCTAssertEqual(workHeaderState(phase: .paused, hasTask: true, observing: true), .paused)
    }

    // The bug: Work Mode on, no task tapped, automatic detection watching. The
    // pill used to say "Paused"; it must say "Watching".
    func testNoTaskWhileObservingIsWatching() {
        XCTAssertEqual(workHeaderState(phase: .paused, hasTask: false, observing: true), .watching)
    }

    // No task and not observing (detection off or no permission): prompt to start.
    func testNoTaskNotObservingIsIdle() {
        XCTAssertEqual(workHeaderState(phase: .paused, hasTask: false, observing: false), .idle)
    }
}
