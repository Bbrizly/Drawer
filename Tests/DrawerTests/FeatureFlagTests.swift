@testable import Drawer
import XCTest

final class FeatureFlagTests: XCTestCase {
    func testTimerFeatureGroupContainsFocusPomodoroAndStopwatch() {
        // The Timers group holds only the three timer pills; they render as cards
        // on the Settings Timers tab, not as toggles in the Features list.
        let timerTitles = FeatureFlag.allCases
            .filter { $0.group == "Timers" }
            .map(\.title)

        XCTAssertEqual(timerTitles, ["Focus timer", "Pomodoro", "Stopwatch"])
    }

    func testTimerAndFocusGroupsAreHiddenFromFeaturesList() {
        // These flags live on the Timers tab, so their groups must stay out of
        // the generic Features list. Presets still reach them via allCases.
        XCTAssertFalse(FeatureFlag.groupsInOrder.contains("Timers"))
        XCTAssertFalse(FeatureFlag.groupsInOrder.contains("Focus"))
    }

    func testPomodoroFeatureDefaultsOnWithStableKey() {
        XCTAssertEqual(FeatureFlag.pomodoro.key, "feature.pomodoro")
        XCTAssertTrue(FeatureFlag.pomodoro.defaultValue)
    }

    func testAttributionIsOptInOffByDefault() {
        XCTAssertEqual(FeatureFlag.attribution.key, "feature.attribution")
        XCTAssertFalse(FeatureFlag.attribution.defaultValue)
    }

    func testAttributionExistsOnlyOutsideAppStoreBuild() {
        // Runs in both flavors: `swift test` and `swift test -Xswiftc -DAPPSTORE`.
        XCTAssertEqual(FeatureFlag.availableCases.contains(.attribution), !appStoreBuild)
        XCTAssertEqual(
            Set(FeatureFlag.availableCases).symmetricDifference(FeatureFlag.allCases),
            appStoreBuild ? [.attribution] : [])
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
