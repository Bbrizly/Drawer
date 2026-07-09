@testable import Drawer
import XCTest

final class FeatureFlagTests: XCTestCase {
    func testTimerFeatureGroupContainsFocusPomodoroAndStopwatch() {
        let timerTitles = FeatureFlag.allCases
            .filter { $0.group == "Timers" }
            .map(\.title)

        XCTAssertEqual(
            timerTitles,
            ["Focus timer", "Pomodoro", "Stopwatch", "Automatic attribution",
             "AI day planner", "Time-travel history"])
    }

    func testPomodoroFeatureDefaultsOnWithStableKey() {
        XCTAssertEqual(FeatureFlag.pomodoro.key, "feature.pomodoro")
        XCTAssertTrue(FeatureFlag.pomodoro.defaultValue)
    }

    func testAttributionIsOptInOffByDefault() {
        XCTAssertEqual(FeatureFlag.attribution.key, "feature.attribution")
        XCTAssertFalse(FeatureFlag.attribution.defaultValue)
    }

    func testFinickyFeaturesShipOff() {
        for flag in [FeatureFlag.planner, .history, .workMode, .ideaCapture] {
            XCTAssertFalse(flag.defaultValue, "\(flag.rawValue) should default off")
        }
        // Everyday features stay on.
        for flag in [FeatureFlag.focusTimer, .ideas, .notes, .swipeDelete] {
            XCTAssertTrue(flag.defaultValue, "\(flag.rawValue) should default on")
        }
    }
}
