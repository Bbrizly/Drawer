import DrawerCore
import Foundation

enum PomodoroPreferences {
    static let focusMinutesKey = "pomodoro.focusMinutes"
    static let shortBreakMinutesKey = "pomodoro.shortBreakMinutes"
    static let longBreakMinutesKey = "pomodoro.longBreakMinutes"
    static let sessionsUntilLongBreakKey = "pomodoro.sessionsUntilLongBreak"

    enum Preset: String, CaseIterable, Identifiable {
        case classic
        case sprint
        case deepWork

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classic: return "Classic"
            case .sprint: return "Sprint"
            case .deepWork: return "Deep work"
            }
        }

        var subtitle: String {
            switch self {
            case .classic: return "25 / 5 / 15"
            case .sprint: return "15 / 3 / 10"
            case .deepWork: return "50 / 10 / 30"
            }
        }

        var settings: PomodoroTimer.Settings {
            switch self {
            case .classic:
                return .standard
            case .sprint:
                return PomodoroTimer.Settings(
                    focusMinutes: 15,
                    shortBreakMinutes: 3,
                    longBreakMinutes: 10,
                    sessionsUntilLongBreak: 4
                )
            case .deepWork:
                return PomodoroTimer.Settings(
                    focusMinutes: 50,
                    shortBreakMinutes: 10,
                    longBreakMinutes: 30,
                    sessionsUntilLongBreak: 2
                )
            }
        }

        static func matching(_ settings: PomodoroTimer.Settings) -> Preset? {
            let clean = settings.sanitized
            return allCases.first { $0.settings == clean }
        }
    }

    static var defaults: [String: Any] {
        let standard = PomodoroTimer.Settings.standard
        return [
            focusMinutesKey: standard.focusMinutes,
            shortBreakMinutesKey: standard.shortBreakMinutes,
            longBreakMinutesKey: standard.longBreakMinutes,
            sessionsUntilLongBreakKey: standard.sessionsUntilLongBreak,
        ]
    }

    static func settings(
        focusMinutes: Int,
        shortBreakMinutes: Int,
        longBreakMinutes: Int,
        sessionsUntilLongBreak: Int
    ) -> PomodoroTimer.Settings {
        PomodoroTimer.Settings(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            sessionsUntilLongBreak: sessionsUntilLongBreak
        ).sanitized
    }
}
