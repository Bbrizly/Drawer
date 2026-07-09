import Foundation
import Observation

/// Which companion pane is showing to the right of the drawer, if any. The pane
/// is opened only by the top-bar buttons; there is no hotkey. `nil` = closed,
/// drawer at its normal width.
enum Pane: String, Equatable, CaseIterable {
    case plan, work, history, settings

    var title: String {
        switch self {
        case .plan: return "Plan today"
        case .work: return "Work"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .plan: return "Plan"
        case .work: return "Work"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .plan: return "calendar"
        case .work: return "chart.bar"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// The single source of truth for the companion pane. App-side and `@Observable`
/// so the drawer view re-renders when it changes; the panel widens/collapses off
/// the same signal.
@Observable
final class PaneRouter {
    var activePane: Pane? {
        didSet { if let pane = activePane { lastOpened = pane } }
    }
    /// The section to reopen to when the pane re-opens (see DrawerView.paneToShow).
    private(set) var lastOpened: Pane = .plan

    /// Switch which section shows (the in-pane segmented control).
    func show(_ pane: Pane) { activePane = pane }
}
