import DrawerCore
import SwiftUI

/// The right-hand companion pane. A visually distinct second column inside the
/// same drawer panel (not a new window), hosting Plan and Work (live) plus
/// History and Settings (upcoming).
struct CompanionPaneView: View {
    let pane: Pane
    /// The sections whose feature is enabled, in display order. The switcher
    /// lists only these, so a disabled feature never shows an empty section.
    var panes: [Pane] = Pane.allCases
    var router: PaneRouter
    /// Drives the Plan pane. Optional so previews/tests can omit the model.
    var planner: PlannerController? = nil
    /// Drives the Work pane (live watching + review). Optional for previews/tests.
    var attribution: AttributionController? = nil
    /// Drives the History pane (snapshot scrubber). Optional for previews/tests.
    var history: HistoryRecorder? = nil
    /// True while the pane is open (not just mounted at width 0), so panes can
    /// refresh on reopen.
    var isActive: Bool = false
    /// Ask the panel to become key so this pane's fields receive typing (the
    /// panel is non-activating, so a focused field alone is not enough).
    var onNeedsKeyboard: () -> Void = {}

    @Environment(\.drawerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().opacity(0.4)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paneBackground)
        .foregroundStyle(theme.primaryInk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Icon segmented switcher: compact enough to sit inside the pane
                // instead of crowding the drawer's top row. Hidden with a single
                // section, where there is nothing to switch between.
                if panes.count > 1 {
                    Picker("Section", selection: paneBinding) {
                        ForEach(panes, id: \.self) { pane in
                            Image(systemName: pane.symbol)
                                .accessibilityLabel(pane.accessibilityLabel)
                                .tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
                DrawerIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "Close pane",
                    helpText: "Close this pane."
                ) {
                    router.activePane = nil
                }
            }
            Text(pane.title)
                .font(theme.uiFont(size: 16, weight: .semibold))
        }
    }

    private var paneBinding: Binding<Pane> {
        Binding(get: { pane }, set: { router.show($0) })
    }

    @ViewBuilder
    private var content: some View {
        // Plan and Work are wired; History and Settings are next.
        switch pane {
        case .plan:
            if let planner {
                PlanPaneView(planner: planner, isActive: isActive, onNeedsKeyboard: onNeedsKeyboard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder("Your accepted plan will show here as a timed schedule. Accepting a plan writes a sidecar, never your task file.")
            }
        case .work:
            if let attribution {
                WorkPaneView(controller: attribution, isActive: isActive)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder("Live work-mode feedback lands here: what Drawer is watching, today's captured blocks, and the hours to confirm.")
            }
        case .history:
            if let history {
                // today is recomputed on each body render so a day rollover
                // reclassifies Today/Carried without rebuilding the pane.
                HistoryScrubberView(recorder: history, today: TodoStore.localToday(), inline: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                placeholder("A time-lapse scrub of your day lives here: watch tasks appear, get checked off, and see which stayed longest.")
            }
        case .settings:
            placeholder("Settings move in here: general, features, board, advanced, and the tracking rules. Inline, no separate window.")
        }
    }

    /// A still-unbuilt pane: its copy text.
    private func placeholder(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(theme.uiFont(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var paneBackground: some View {
        // The shared panel plate already sits behind this column (drawn by
        // DrawerView), so the pane only adds a faint theme-ink wash to read as a
        // distinct column, plus a hairline divider from the task list. Both pull
        // from the theme so every theme's pane looks native, never a clear void.
        theme.primaryInk.opacity(0.05)
            .overlay(alignment: .leading) {
                theme.primaryInk.opacity(0.12)
                    .frame(width: 1)
            }
    }
}
