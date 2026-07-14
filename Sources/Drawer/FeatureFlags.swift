import SwiftUI

/// True in the Mac App Store flavor (`make appstore`, i.e. -DAPPSTORE). The
/// sandbox denies the Accessibility API, so the AX-dependent surface
/// (attribution sampling, the right-Command tap) is unreachable in that build:
/// no toggle, no prompt, no monitor.
#if APPSTORE
    let appStoreBuild = true
#else
    let appStoreBuild = false
#endif

/// Every switchable feature in the app. One source of truth so the Settings
/// list and the Minimal/Everything presets iterate generically, while each
/// view reads a single key via @AppStorage. The four pre-existing toggles
/// keep their original UserDefaults keys so saved preferences carry over.
enum FeatureFlag: String, CaseIterable, Identifiable {
    case focusTimer
    case pomodoro
    case focusSound
    case timerEndSound
    case confetti
    case checkOffPop
    case swipeDelete
    case swipeProgress
    case taskNotes
    case minuteBadges
    case notes
    case filterMenu
    case carriedSection
    case tomorrowSection
    case backlogSection
    case archiveSection
    case workMode
    /// Watches the frontmost app and window title to propose work sessions you
    /// approve in a review queue. Off by default: explicit opt-in, needs
    /// Accessibility permission. Nothing is written without your approval.
    case attribution
    /// One-button on-device day planner. Default on, but the button only appears
    /// when Apple Foundation Models is available (checked at render time).
    case planner
    /// A view-only time-travel scrubber over Drawer.md's recent history.
    case history
    case ideas
    /// The light-bulb capture bar (jot + Park). Split from `ideas` so the board
    /// can stay on while the finicky park animation stays off. Off by default.
    case ideaCapture
    /// Exposes Drawer to AI agents over MCP (a separate `drawer-mcp` binary you
    /// register with `claude mcp add`). The app doesn't run the server, so this
    /// flag gates nothing in-app in v1; it exists, defaults on, and is kept out
    /// of `groupsInOrder` so it renders no dead toggle. A Pro tier can read it
    /// later to wrap the integration.
    case mcp
    /// The Papers-Please rummage drawer (see Docs/bureau-spec.md). Off by
    /// default; the toggle lives in Settings > Features under "Bureau".
    /// Deleting the `DrawerBureau` target leaves the app exactly as it is
    /// today.
    case bureau

    var id: String { rawValue }

    var key: String {
        switch self {
        case .confetti: return "taskCelebration"
        case .checkOffPop: return "taskCelebrationSound"
        case .timerEndSound: return "completionSound"
        case .tomorrowSection: return "showTomorrow"
        default: return "feature.\(rawValue)"
        }
    }

    var title: String {
        switch self {
        case .focusTimer: return "Focus timer"
        case .pomodoro: return "Pomodoro"
        case .focusSound: return "Focus sound"
        case .timerEndSound: return "Sound when timer ends"
        case .confetti: return "Celebrate completed tasks"
        case .checkOffPop: return "Sound on check-off"
        case .swipeDelete: return "Swipe to delete"
        case .swipeProgress: return "Swipe to mark in progress"
        case .taskNotes: return "Task notes"
        case .minuteBadges: return "Minute badges"
        case .notes: return "Notes pad"
        case .filterMenu: return "Filter menu"
        case .carriedSection: return "Carried-over section"
        case .tomorrowSection: return "Tomorrow section"
        case .backlogSection: return "Backlog section"
        case .archiveSection: return "Archive section"
        case .workMode: return "Stopwatch"
        case .attribution: return "Automatic attribution"
        case .planner: return "AI day planner"
        case .history: return "Time-travel history"
        case .ideas: return "Idea board"
        case .ideaCapture: return "Idea capture bar"
        case .mcp: return "MCP server"
        case .bureau: return "The Bureau"
        }
    }

    var blurb: String {
        switch self {
        case .focusTimer: return "The countdown pill in the header."
        case .pomodoro: return "A focus, short break, long break cycle in the header."
        case .focusSound: return "A speaker button to play pink or brown noise."
        case .timerEndSound: return "Chime and notification when a session ends."
        case .confetti: return "Confetti and a haptic tap on completion."
        case .checkOffPop: return "A sound each time you check a task off. Pick which one under General."
        case .swipeDelete: return "Swipe a row left to reveal delete."
        case .swipeProgress: return "Swipe a row right to flag it in progress."
        case .taskNotes: return "Expand a task to read or edit a description."
        case .minuteBadges: return "The duration pill on a task."
        case .notes: return "A scratchpad in the header, with a teleprompter."
        case .filterMenu: return "Hide completed and unchecked-first options."
        case .carriedSection: return "Unfinished tasks pulled from earlier days."
        case .tomorrowSection: return "The next planned day, for evening planning."
        case .backlogSection: return "Collapsible Backlog at the bottom."
        case .archiveSection: return "Collapsible Archive at the bottom."
        case .workMode: return "A stopwatch that logs real hours against tasks."
        case .attribution: return "Watch app and window to propose sessions you approve. Off by default."
        case .planner: return "A button that drafts a day plan with calibrated durations. Needs Apple Intelligence."
        case .history: return "Scrub through recent versions of your drawer. View-only."
        case .ideas: return "A board of parked ideas you swipe to."
        case .ideaCapture: return "A light bulb to jot an idea and park it on the board. Off by default; rough edges."
        case .mcp: return "Let AI agents read and write your drawer over MCP."
        case .bureau: return "A rummage drawer of receipt-notes for the week's tasks. Queue tasks from the row menu, then flip the tray button."
        }
    }

    var group: String {
        switch self {
        // "Timers" and "Focus" are absent from groupsInOrder: these flags are
        // presented as dedicated controls on the Settings Timers tab, not as
        // generic toggles in the Features list. Presets still reach them.
        case .focusTimer, .pomodoro, .workMode: return "Timers"
        case .focusSound, .timerEndSound: return "Focus"
        case .confetti, .checkOffPop: return "Feedback"
        case .swipeDelete, .swipeProgress: return "Swipe gestures"
        case .taskNotes, .minuteBadges: return "Task rows"
        case .carriedSection, .tomorrowSection, .backlogSection, .archiveSection: return "Sections"
        case .filterMenu, .notes, .ideas, .ideaCapture, .history: return "Controls"
        case .attribution, .planner: return "Automation"
        // "Integrations" is intentionally absent from groupsInOrder, so this
        // flag exists without rendering a toggle (see the case comment).
        case .mcp: return "Integrations"
        case .bureau: return "Bureau"
        }
    }

    /// Value under the Minimal preset. Only the carried-over list survives,
    /// since unfinished work is the whole point of the app. Everything else
    /// strips away, including today's section header chrome (Today always
    /// renders, it is not a flag).
    var minimalValue: Bool { self == .carriedSection }

    /// Default when never set. The finicky, watch-heavy features ship off:
    /// they are explicit opt-ins the user turns on when wanted, and staying off
    /// keeps launch lightweight (no sampler, no snapshot timer, no on-device
    /// model). Everything else stays on.
    var defaultValue: Bool {
        switch self {
        case .attribution, .planner, .history, .workMode, .ideaCapture, .bureau: return false
        default: return true
        }
    }

    static let groupsInOrder = [
        "Feedback", "Swipe gestures", "Task rows", "Sections", "Controls", "Automation", "Bureau",
    ]

    /// The flags that exist in this build. The App Store build drops
    /// attribution: its AX sampling is denied by the sandbox.
    static var availableCases: [FeatureFlag] {
        appStoreBuild ? allCases.filter { $0 != .attribution } : allCases
    }

    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        for flag in availableCases { defaults[flag.key] = flag.defaultValue }
        UserDefaults.standard.register(defaults: defaults)
    }
}

/// Drives the Settings feature list. The live drawer views read the same keys
/// via @AppStorage, so a preset applied here updates them automatically
/// through UserDefaults change notifications.
@MainActor
final class FeatureFlagsModel: ObservableObject {
    func binding(_ flag: FeatureFlag) -> Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: flag.key) as? Bool ?? flag.defaultValue },
            set: { [weak self] in
                UserDefaults.standard.set($0, forKey: flag.key)
                self?.objectWillChange.send()
            }
        )
    }

    func applyMinimal() {
        for flag in FeatureFlag.availableCases {
            UserDefaults.standard.set(flag.minimalValue, forKey: flag.key)
        }
        objectWillChange.send()
    }

    func applyEverything() {
        for flag in FeatureFlag.availableCases {
            UserDefaults.standard.set(true, forKey: flag.key)
        }
        objectWillChange.send()
    }
}
