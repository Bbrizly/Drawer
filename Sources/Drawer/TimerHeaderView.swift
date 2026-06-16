import DrawerCore
import SwiftUI

struct TimerHeaderView: View {
    @ObservedObject var timer: FocusTimer
    @AppStorage("defaultMinutesText") private var minutesText = "25"
    @Environment(\.drawerTheme) private var theme

    var body: some View {
        switch timer.phase {
        case .idle:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("FOCUS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        TextField("25", text: $minutesText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .frame(width: 36)
                            .accessibilityLabel("Focus duration")
                            .accessibilityHint("Enter the focus timer duration in minutes.")
                            .onChange(of: minutesText) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(3))
                                if digits != newValue { minutesText = digits }
                            }
                            .onSubmit(start)
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }

                DrawerIconButton(
                    systemName: "play.fill",
                    accessibilityLabel: "Start focus timer",
                    helpText: "Start the focus timer.",
                    isProminent: true,
                    action: start
                )
            }
            .padding(.leading, 11)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            // A thin outline, not a filled pill, so the idle timer reads as a
            // plain control instead of looking permanently selected.
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        case .running, .paused:
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.phase == .running ? "FOCUSING" : "PAUSED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(
                            timer.phase == .running
                                ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                        )
                    Text(FocusTimer.format(timer.remaining))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)
                            .monospacedDigit())
                }
                Spacer()
                if timer.phase == .running {
                    DrawerIconButton(
                        systemName: "pause.fill",
                        accessibilityLabel: "Pause focus timer",
                        helpText: "Pause the current focus session.",
                        isProminent: true
                    ) {
                        timer.pause()
                    }
                } else {
                    DrawerIconButton(
                        systemName: "play.fill",
                        accessibilityLabel: "Resume focus timer",
                        helpText: "Resume the focus timer.",
                        isProminent: true
                    ) {
                        timer.resume()
                    }
                }
                DrawerIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "Reset focus timer",
                    helpText: "Stop and reset the focus timer."
                ) {
                    timer.reset()
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func start() {
        let n = Int(minutesText.trimmingCharacters(in: .whitespaces)) ?? 25
        timer.start(taskTitle: "Focus", minutes: max(1, min(480, n)))
    }
}
