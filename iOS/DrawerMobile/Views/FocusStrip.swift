import DrawerCore
import SwiftUI

struct FocusStrip: View {
    @ObservedObject private var model: DrawerMobileModel
    @Bindable private var timer: FocusTimer

    init(model: DrawerMobileModel) {
        self.model = model
        _timer = Bindable(wrappedValue: model.focusTimer)
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(DrawerPalette.accent)
                .frame(width: 4)
                .clipShape(Capsule())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(timer.phase == .finished ? "Focus complete" : "Focusing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrawerPalette.accent)
                    .lineLimit(1)
                Text(timer.phase == .finished ? timer.taskTitle : timer.taskTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if timer.phase == .finished {
                Button("Close") {
                    model.resetFocus()
                    DrawerHaptics.shared.focusDismissed()
                    DrawerActionFeedbackCenter.announce("Focus session closed")
                }
                .font(.subheadline.weight(.bold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .accessibilityHint("Closes the timer without changing the task")
            } else {
                Text(FocusTimer.format(timer.remaining))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(DrawerPalette.ink)

                Button {
                    switch timer.phase {
                    case .running:
                        model.pauseFocus()
                        DrawerHaptics.shared.focusPaused()
                    case .paused:
                        model.resumeFocus()
                        DrawerHaptics.shared.focusStarted()
                    case .idle, .finished:
                        break
                    }
                } label: {
                    Image(systemName: timer.phase == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(DrawerPalette.ink, in: Circle())
                        .foregroundStyle(DrawerPalette.canvas)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.91, pressedOpacity: 0.96))
                .accessibilityLabel(timer.phase == .running ? "Pause focus" : "Resume focus")

                Button {
                    model.resetFocus()
                    DrawerHaptics.shared.focusDismissed()
                    DrawerActionFeedbackCenter.announce("Focus ended")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.91, pressedOpacity: 0.96))
                .accessibilityLabel("End focus")
                .accessibilityHint("Stops the timer without changing the task")
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .background(DrawerPalette.surface)
        .accessibilityElement(children: .contain)
    }
}
