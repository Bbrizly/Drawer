import DrawerCore
import SwiftUI

struct TimerHeaderView: View {
    var timer: FocusTimer
    @AppStorage("defaultMinutesText") private var minutesText = "25"
    @Environment(\.drawerTheme) private var theme

    private var labelFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 9, weight: .bold)
            : .system(size: 9, weight: .bold)
    }

    private var timeFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 22, weight: .semibold).monospacedDigit()
            : .system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var body: some View {
        switch timer.phase {
        case .idle:
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Focus")
                        .font(labelFont)
                        .tracking(theme.usesXPChrome ? 0 : 0.8)
                        .foregroundStyle(.tertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        TextField("25", text: $minutesText)
                            .textFieldStyle(.plain)
                            .font(timeFont)
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
                            .font(theme.uiFont(size: 12))
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
            .xpTimerWidth(theme)
            .background { timerChrome(outlined: true) }
        case .running, .paused:
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.phase == .running ? "Focusing" : "Paused")
                        .font(labelFont)
                        .tracking(theme.usesXPChrome ? 0 : 0.8)
                        .foregroundStyle(
                            timer.phase == .running
                                ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                        )
                    Text(FocusTimer.format(timer.remaining))
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 25, weight: .semibold).monospacedDigit()
                              : .system(size: 25, weight: .semibold, design: .rounded).monospacedDigit())
                }
                if timer.phase == .running {
                    DrawerIconButton(
                        systemName: "pause.fill",
                        accessibilityLabel: "Pause focus timer",
                        helpText: "Pause the current focus session.",
                        isProminent: true,
                        size: 28,
                        iconSize: 12
                    ) {
                        timer.pause()
                    }
                } else {
                    DrawerIconButton(
                        systemName: "play.fill",
                        accessibilityLabel: "Resume focus timer",
                        helpText: "Resume the focus timer.",
                        isProminent: true,
                        size: 28,
                        iconSize: 12
                    ) {
                        timer.resume()
                    }
                }
                DrawerIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "Reset focus timer",
                    helpText: "Stop and reset the focus timer.",
                    size: 28,
                    iconSize: 12
                ) {
                    timer.reset()
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.vertical, 7)
            .xpTimerWidth(theme)
            .background { timerChrome(outlined: false) }
        case .finished:
            HStack(spacing: 10) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.onAccent)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time's up")
                        .font(labelFont)
                        .tracking(theme.usesXPChrome ? 0 : 0.8)
                        .foregroundStyle(Palette.onAccent.opacity(0.85))
                    Text(timer.taskTitle.isEmpty ? "Focus done" : timer.taskTitle)
                        .font(theme.usesXPChrome
                              ? FontLoader.xpFont(size: 15, weight: .semibold)
                              : .system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.onAccent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                }
                Button {
                    timer.reset()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            theme.usesXPChrome ? AnyShapeStyle(Color.white) : AnyShapeStyle(Palette.onAccent),
                            in: theme.usesXPChrome ? AnyShape(Rectangle()) : AnyShape(Circle())
                        )
                        .contentShape(theme.usesXPChrome ? AnyShape(Rectangle()) : AnyShape(Circle()))
                }
                .buttonStyle(.plain)
                .help("Dismiss the finished timer.")
                .accessibilityLabel("Dismiss finished timer")
            }
            .padding(.leading, 11)
            .padding(.trailing, 7)
            .padding(.vertical, 9)
            .xpTimerWidth(theme)
            .background {
                if theme.usesXPChrome {
                    Rectangle().fill(Palette.xpSelection)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.accent.gradient)
                }
            }
        }
    }

    @ViewBuilder
    private func timerChrome(outlined: Bool) -> some View {
        if theme.usesXPChrome {
            XPSunkenPanel()   // XP sinks the timer well the same way either state
        } else if outlined {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
    }

    private func start() {
        let n = Int(minutesText.trimmingCharacters(in: .whitespaces)) ?? 25
        timer.start(taskTitle: "Focus", minutes: max(1, min(480, n)))
    }
}
