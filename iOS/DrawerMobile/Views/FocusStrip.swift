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
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: timer.phase == .finished ? "checkmark" : "timer")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.tint)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(timer.phase == .finished ? "Focus complete" : timer.taskTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(timer.phase == .finished ? timer.taskTitle : FocusTimer.format(timer.remaining))
                    .font(timer.phase == .finished ? .caption : .system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
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
                        .background(.quaternary.opacity(0.6), in: Circle())
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
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(timer.phase == .finished ? 0.22 : 0.10), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
    }
}
