import DrawerCore
import SwiftUI

/// The header pill while Work Mode is on. Mirrors `TimerHeaderView`'s running
/// state: a state label, the task's running total for today, the task name, and
/// a pause/resume button. Ending work mode lives on the briefcase toggle in the
/// header, not here.
struct WorkModeHeaderView: View {
    var clock: WorkClock
    @Environment(\.drawerTheme) private var theme

    private var running: Bool { clock.phase == .running }
    private var hasTask: Bool { !clock.activeTaskTitle.isEmpty }

    private var labelFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 9, weight: .bold)
            : .system(size: 9, weight: .bold)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(running ? "Working" : "Paused")
                    .font(labelFont)
                    .tracking(theme.usesXPChrome ? 0 : 0.8)
                    .foregroundStyle(
                        running ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                    )
                Text(WorkClock.formatHM(clock.activeTaskTotal))
                    .font(theme.usesXPChrome
                          ? FontLoader.xpFont(size: 26, weight: .semibold).monospacedDigit()
                          : .system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                Text(hasTask ? clock.activeTaskTitle : "Tap a task to start")
                    .font(theme.usesXPChrome
                          ? FontLoader.xpFont(size: 10, weight: .regular)
                          : .system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            if hasTask {
                if running {
                    DrawerIconButton(
                        systemName: "pause.fill",
                        accessibilityLabel: "Pause work timer",
                        helpText: "Pause time tracking on this task.",
                        isProminent: true
                    ) {
                        clock.pause()
                    }
                } else {
                    DrawerIconButton(
                        systemName: "play.fill",
                        accessibilityLabel: "Resume work timer",
                        helpText: "Resume time tracking on this task.",
                        isProminent: true
                    ) {
                        clock.resume()
                    }
                }
            }
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
}
