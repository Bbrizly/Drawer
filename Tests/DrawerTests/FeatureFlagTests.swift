@testable import Drawer
import XCTest

final class FeatureFlagTests: XCTestCase {
    func testTimerFeatureGroupContainsFocusPomodoroAndStopwatch() {
        let timerTitles = FeatureFlag.allCases
            .filter { $0.group == "Timers" }
            .map(\.title)

        XCTAssertEqual(timerTitles, ["Focus timer", "Pomodoro", "Stopwatch"])
    }

    func testPomodoroFeatureDefaultsOnWithStableKey() {
        XCTAssertEqual(FeatureFlag.pomodoro.key, "feature.pomodoro")
        XCTAssertTrue(FeatureFlag.pomodoro.defaultValue)
    }
}
