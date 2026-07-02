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

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(running ? "WORKING" : "PAUSED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(
                        running ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                    )
                Text(WorkClock.formatHM(clock.activeTaskTotal))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)
                        .monospacedDigit())
                Text(hasTask ? clock.activeTaskTitle : "Tap a task to start")
                    .font(.system(size: 10, weight: .medium))
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
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        // No horizontal fixedSize: when the header row runs out of room the
        // task title truncates instead of forcing the panel wider.
    }
}
