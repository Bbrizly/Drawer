import DrawerCore
import SwiftUI

/// The header pill while Work Mode is on. It reads one of four states (see
/// `workHeaderState`): hand-tracking a task ("Working"), a task paused by hand
/// ("Paused"), automatic detection watching the frontmost app with no task
/// tapped ("Watching"), or nothing yet ("Tap a task to start"). Ending work mode
/// lives on the briefcase toggle in the header, not here.
///
/// The watching branch needs the attribution controller's live `isObserving` and
/// `liveSample`, so an inner `@ObservedObject` subview does the observing; the
/// clock alone cannot tell "watching" from "paused".
struct WorkModeHeaderView: View {
    var clock: WorkClock
    var attribution: AttributionController?

    var body: some View {
        if let attribution {
            ObservingWorkModeHeader(clock: clock, controller: attribution)
        } else {
            // No attribution wired: detection can never be observing, so the pill
            // only ever shows the manual clock states.
            WorkHeaderPill(clock: clock, observing: false, sample: nil, capturedToday: 0)
        }
    }
}

/// Observes the attribution controller so a change in `isObserving` or the live
/// sample refreshes the pill, then hands both to the stateless `WorkHeaderPill`.
private struct ObservingWorkModeHeader: View {
    var clock: WorkClock
    @ObservedObject var controller: AttributionController

    var body: some View {
        WorkHeaderPill(
            clock: clock,
            observing: controller.isObserving,
            sample: controller.liveSample,
            capturedToday: controller.todaySummary.total
        )
    }
}

private struct WorkHeaderPill: View {
    var clock: WorkClock
    var observing: Bool
    var sample: ActivitySample?
    /// Total time auto-detection has captured today (confirmed + pending). Shown
    /// as the running number while watching, so the timer reads as live, not paused.
    var capturedToday: TimeInterval

    @Environment(\.drawerTheme) private var theme

    private var state: WorkHeaderState {
        workHeaderState(
            phase: clock.phase,
            hasTask: !clock.activeTaskTitle.isEmpty,
            observing: observing
        )
    }

    private var labelFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 9, weight: .bold)
            : .system(size: 9, weight: .bold)
    }

    private var totalFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 26, weight: .semibold).monospacedDigit()
            : .system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
    }

    private var subtitleFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 10, weight: .regular)
            : .system(size: 10, weight: .medium)
    }

    /// The top state word, tinted to read as live (accent) or idle (secondary).
    private var stateLabel: (text: String, active: Bool) {
        switch state {
        case .working:  return ("Working", true)
        case .paused:   return ("Paused", false)
        case .watching: return ("Watching", true)
        case .idle:     return ("Paused", false)
        }
    }

    /// The big number. For watching there is no active task, so show today's
    /// captured total instead of a stalled 0h 00m on a task no one picked.
    private var totalSeconds: TimeInterval {
        state == .watching ? capturedToday : clock.activeTaskTotal
    }

    private var subtitle: String {
        switch state {
        case .working, .paused:
            return clock.activeTaskTitle.isEmpty ? "Tap a task to start" : clock.activeTaskTitle
        case .watching:
            return watchTarget
        case .idle:
            return "Tap a task to start"
        }
    }

    /// The frontmost app being watched, e.g. "Xcode: WorkClock.swift". Falls back
    /// to a plain prompt before the first sample lands.
    private var watchTarget: String {
        guard let sample else { return "Detecting your work" }
        guard let title = sample.windowTitle, !title.isEmpty else { return sample.appName }
        return "\(sample.appName): \(title)"
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(stateLabel.text)
                    .font(labelFont)
                    .tracking(theme.usesXPChrome ? 0 : 0.8)
                    .foregroundStyle(
                        stateLabel.active ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                    )
                Text(WorkClock.formatHM(totalSeconds))
                    .font(totalFont)
                Text(subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160, alignment: .leading)
            }

            trailingControl
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background {
            if theme.usesXPChrome {
                XPSunkenPanel()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
            }
        }
    }

    /// Pause/resume only makes sense for a hand-tracked task. Watching is driven
    /// by the sampler and ended from the briefcase toggle, so it has no button.
    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .working:
            DrawerIconButton(
                systemName: "pause.fill",
                accessibilityLabel: "Pause work timer",
                helpText: "Pause time tracking on this task.",
                isProminent: true
            ) {
                clock.pause()
            }
        case .paused:
            DrawerIconButton(
                systemName: "play.fill",
                accessibilityLabel: "Resume work timer",
                helpText: "Resume time tracking on this task.",
                isProminent: true
            ) {
                clock.resume()
            }
        default:
            EmptyView()
        }
    }
}
