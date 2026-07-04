import DrawerCore
@testable import Drawer
import XCTest

final class PomodoroPreferencesTests: XCTestCase {
    func testPomodoroPresetsUseIntentionalCadences() {
        XCTAssertEqual(
            PomodoroPreferences.Preset.allCases.map(\.title),
            ["Classic", "Sprint", "Deep work"]
        )
        XCTAssertEqual(PomodoroPreferences.Preset.classic.settings, .standard)
        XCTAssertEqual(
            PomodoroPreferences.Preset.sprint.settings,
            PomodoroTimer.Settings(
                focusMinutes: 15,
                shortBreakMinutes: 3,
                longBreakMinutes: 10,
                sessionsUntilLongBreak: 4
            )
        )
        XCTAssertEqual(
            PomodoroPreferences.Preset.deepWork.settings,
            PomodoroTimer.Settings(
                focusMinutes: 50,
                shortBreakMinutes: 10,
                longBreakMinutes: 30,
                sessionsUntilLongBreak: 2
            )
        )
    }

    func testMatchingPresetReturnsNilForCustomCadence() {
        XCTAssertEqual(
            PomodoroPreferences.Preset.matching(.standard),
            .classic
        )
        XCTAssertNil(
            PomodoroPreferences.Preset.matching(
                PomodoroTimer.Settings(
                    focusMinutes: 32,
                    shortBreakMinutes: 6,
                    longBreakMinutes: 18,
                    sessionsUntilLongBreak: 4
                )
            )
        )
    }
}
