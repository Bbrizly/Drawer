import XCTest
@testable import DrawerCore

@MainActor
final class AttributionActivationTests: XCTestCase {
    // Work Mode off and permitted: the watcher stands down and the day gets its
    // AI summary.
    func testWorkModeOffEndsTheSessionWhenPermitted() {
        XCTAssertEqual(attributionActivation(workPhase: .off, permitted: true), .endSession)
    }

    // Work Mode off but not permitted: the user disabled automatic attribution,
    // so ending Work Mode must not write an AI day summary. Suspend, don't end.
    func testWorkModeOffSuspendsWhenNotPermitted() {
        XCTAssertEqual(attributionActivation(workPhase: .off, permitted: false), .suspend)
    }

    // Work Mode on, no task being hand-tracked: observe (only when permitted).
    func testWatchingWhenPermittedAndNoTask() {
        XCTAssertEqual(attributionActivation(workPhase: .paused, permitted: true), .observe)
    }

    // Permission not granted: never observe, but this is not the end of the day.
    func testNoObserveWithoutPermission() {
        XCTAssertEqual(attributionActivation(workPhase: .paused, permitted: false), .suspend)
    }

    // Hand-tracking a task: you've said what you're doing, so the watcher stands
    // down, but the work session is still going, so no day summary yet.
    func testHandTrackingSuspends() {
        XCTAssertEqual(attributionActivation(workPhase: .running, permitted: true), .suspend)
        XCTAssertEqual(attributionActivation(workPhase: .running, permitted: false), .suspend)
    }
}
