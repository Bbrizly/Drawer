import DrawerCore
import SwiftUI

struct PomodoroHeaderView: View {
    var timer: PomodoroTimer

    @AppStorage(PomodoroPreferences.focusMinutesKey) private var focusMinutes =
        PomodoroTimer.Settings.standard.focusMinutes
    @AppStorage(PomodoroPreferences.shortBreakMinutesKey) private var shortBreakMinutes =
        PomodoroTimer.Settings.standard.shortBreakMinutes
    @AppStorage(PomodoroPreferences.longBreakMinutesKey) private var longBreakMinutes =
        PomodoroTimer.Settings.standard.longBreakMinutes
    @AppStorage(PomodoroPreferences.sessionsUntilLongBreakKey) private var sessionsUntilLongBreak =
        PomodoroTimer.Settings.standard.sessionsUntilLongBreak
    @Environment(\.drawerTheme) private var theme
    @State private var showSegmentChooser = false

    private var settings: PomodoroTimer.Settings {
        PomodoroPreferences.settings(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            sessionsUntilLongBreak: sessionsUntilLongBreak
        )
    }

    private var labelFont: Font {
        theme.usesXPChrome
            ? FontLoader.xpFont(size: 9, weight: .bold)
            : .system(size: 9, weight: .bold)
    }

    var body: some View {
        Group {
            switch timer.phase {
            case .idle:
                HStack(spacing: 8) {
                    segmentRing(progress: 0, foreground: theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.segment.stateLabel(paused: false))
                            .font(labelFont)
                            .tracking(theme.usesXPChrome ? 0 : 0.8)
                            .foregroundStyle(theme.accent)
                        Text("\(settings.minutes(for: timer.segment)) min")
                            .font(theme.usesXPChrome
                                  ? FontLoader.xpFont(size: 20, weight: .semibold).monospacedDigit()
                                  : .system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    DrawerIconButton(
                        systemName: "play.fill",
                        accessibilityLabel: "Start Pomodoro",
                        helpText: "Start the selected Pomodoro segment.",
                        isProminent: true,
                        size: 28,
                        iconSize: 12
                    ) {
                        timer.start(settings: settings)
                    }
                }
                .padding(.leading, 7)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .xpTimerWidth(theme)
                .background {
                    if theme.usesXPChrome {
                        XPSunkenPanel()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
                }
            case .running, .paused:
                HStack(spacing: 7) {
                    segmentRing(
                        progress: timer.progress(settings: settings),
                        foreground: timer.phase == .running ? theme.accent : theme.secondaryInk
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.segment.stateLabel(paused: timer.phase == .paused))
                            .font(labelFont)
                            .tracking(theme.usesXPChrome ? 0 : 0.8)
                            .foregroundStyle(
                                timer.phase == .running
                                    ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary)
                            )
                        Text(PomodoroTimer.format(timer.remaining))
                            .font(theme.usesXPChrome
                                  ? FontLoader.xpFont(size: 24, weight: .semibold).monospacedDigit()
                                  : .system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        PomodoroCycleDots(
                            completed: timer.completedFocusSessions,
                            cadence: settings.sessionsUntilLongBreak,
                            segment: timer.segment,
                            phase: timer.phase
                        )
                    }
                    if timer.phase == .running {
                        DrawerIconButton(
                            systemName: "pause.fill",
                            accessibilityLabel: "Pause Pomodoro",
                            helpText: "Pause the Pomodoro timer.",
                            isProminent: true,
                            size: 28,
                            iconSize: 12
                        ) {
                            timer.pause()
                        }
                    } else {
                        DrawerIconButton(
                            systemName: "play.fill",
                            accessibilityLabel: "Resume Pomodoro",
                            helpText: "Resume the Pomodoro timer.",
                            isProminent: true,
                            size: 28,
                            iconSize: 12
                        ) {
                            timer.resume()
                        }
                    }
                    DrawerIconButton(
                        systemName: "xmark",
                        accessibilityLabel: "Reset Pomodoro",
                        helpText: "Stop and reset the Pomodoro timer.",
                        size: 28,
                        iconSize: 12
                    ) {
                        timer.reset()
                    }
                }
                .padding(.leading, 7)
                .padding(.trailing, 5)
                .padding(.vertical, 6)
                .xpTimerWidth(theme)
                .background {
                    if theme.usesXPChrome {
                        XPSunkenPanel()
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary.opacity(0.55))
                    }
                }
            case .finished:
                HStack(spacing: 9) {
                    Image(systemName: timer.segment.finishedIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.onAccent)
                        .symbolEffect(.pulse, options: .repeating)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.segment.finishedTitle)
                            .font(labelFont)
                            .tracking(theme.usesXPChrome ? 0 : 0.8)
                            .foregroundStyle(Palette.onAccent.opacity(0.85))
                        Text("Next: \(timer.nextSegment(settings: settings).title)")
                            .font(theme.usesXPChrome
                                  ? FontLoader.xpFont(size: 14, weight: .semibold)
                                  : .system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.onAccent)
                            .lineLimit(1)
                    }
                    Button {
                        timer.startNext(settings: settings)
                    } label: {
                        Image(systemName: "arrow.right")
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
                    .help("Start the next Pomodoro segment.")
                    .accessibilityLabel("Start next Pomodoro segment")
                    Button {
                        timer.reset()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.onAccent.opacity(0.9))
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss Pomodoro")
                    .accessibilityLabel("Dismiss Pomodoro")
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
        .animation(.snappy(duration: 0.22), value: timer.phase)
        .animation(.snappy(duration: 0.22), value: timer.segment)
    }

    @ViewBuilder
    private func segmentRing(progress: Double, foreground: Color) -> some View {
        PomodoroRingButton(
            segment: timer.segment,
            progress: progress,
            foreground: foreground,
            background: theme.tertiaryInk.opacity(0.24),
            isOpen: showSegmentChooser
        ) {
            showSegmentChooser.toggle()
        }
        .popover(isPresented: $showSegmentChooser, arrowEdge: .bottom) {
            PomodoroSegmentChooser(
                selected: timer.segment,
                settings: settings,
                select: { segment in
                    withAnimation(.snappy(duration: 0.22)) {
                        timer.select(segment: segment, settings: settings)
                        showSegmentChooser = false
                    }
                }
            )
            .environment(\.drawerTheme, theme)
            .preferredColorScheme(theme.popoverColorScheme)
        }
    }
}

private struct PomodoroRingButton: View {
    let segment: PomodoroTimer.Segment
    let progress: Double
    let foreground: Color
    let background: Color
    let isOpen: Bool
    let action: () -> Void

    @Environment(\.drawerTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PomodoroRing(
                segment: segment,
                progress: progress,
                foreground: foreground,
                background: background
            )
            .frame(width: 30, height: 30)
            .padding(4)
            .background(
                Circle()
                    .fill(isOpen || isHovering ? theme.accent.opacity(0.13) : Color.clear)
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        theme.accent.opacity(isOpen ? 0.45 : isHovering ? 0.20 : 0),
                        lineWidth: 1
                    )
            )
            .contentShape(Circle())
        }
        .buttonStyle(PomodoroRingButtonStyle())
        .accessibilityLabel("Choose Pomodoro segment")
        .accessibilityHint("Pick focus, short break, or long break.")
        .help("Choose Pomodoro segment")
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }
}

private struct PomodoroRingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

private struct PomodoroSegmentChooser: View {
    let selected: PomodoroTimer.Segment
    let settings: PomodoroTimer.Settings
    let select: (PomodoroTimer.Segment) -> Void

    @Environment(\.drawerTheme) private var theme

    private let segments: [PomodoroTimer.Segment] = [.focus, .shortBreak, .longBreak]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments, id: \.self) { segment in
                Button {
                    select(segment)
                } label: {
                    HStack(spacing: 9) {
                        PomodoroRing(
                            segment: segment,
                            progress: segment == selected ? 0.18 : 0,
                            foreground: segment == selected ? theme.accent : theme.secondaryInk,
                            background: theme.tertiaryInk.opacity(0.22)
                        )
                        .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(segment.title)
                                .font(theme.uiFont(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.primaryInk)
                            Text("\(settings.minutes(for: segment)) minutes")
                                .font(theme.uiFont(size: 12))
                                .foregroundStyle(theme.secondaryInk)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 12)
                        if segment == selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(segment == selected
                                  ? theme.accent.opacity(0.13)
                                  : theme.primaryInk.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Use \(segment.title)")
            }
        }
        .padding(10)
        .frame(width: 190)
    }
}

private struct PomodoroRing: View {
    let segment: PomodoroTimer.Segment
    let progress: Double
    let foreground: Color
    let background: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(background, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(foreground, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: segment.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foreground)
        }
        .frame(width: 28, height: 28)
    }
}

private struct PomodoroCycleDots: View {
    let completed: Int
    let cadence: Int
    let segment: PomodoroTimer.Segment
    let phase: PomodoroTimer.Phase
    @Environment(\.drawerTheme) private var theme

    private var filledCount: Int {
        let remainder = completed % cadence
        guard completed > 0 else { return 0 }
        if remainder == 0 {
            return segment == .focus && phase != .finished ? 0 : cadence
        }
        return remainder
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<cadence, id: \.self) { index in
                Circle()
                    .fill(index < filledCount ? theme.accent : theme.tertiaryInk.opacity(0.28))
                    .frame(width: 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension PomodoroTimer.Segment {
    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "target"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "sparkles"
        }
    }

    var finishedIcon: String {
        switch self {
        case .focus: return "figure.cooldown"
        case .shortBreak, .longBreak: return "target"
        }
    }

    var finishedTitle: String {
        switch self {
        case .focus: return "FOCUS DONE"
        case .shortBreak: return "BREAK DONE"
        case .longBreak: return "RESET READY"
        }
    }

    func stateLabel(paused: Bool) -> String {
        if paused { return "PAUSED" }
        switch self {
        case .focus: return "FOCUS"
        case .shortBreak: return "SHORT BREAK"
        case .longBreak: return "LONG BREAK"
        }
    }
}

private extension PomodoroTimer.Settings {
    func minutes(for segment: PomodoroTimer.Segment) -> Int {
        Int(duration(for: segment) / 60)
    }
}
