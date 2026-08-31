import SwiftUI

struct QuickCaptureBar: View {
    @ObservedObject var model: DrawerMobileModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var destination: DrawerTaskDestination = .today
    @State private var actionFeedback: DrawerActionFeedbackPayload?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let undoLabel = model.undoLabel {
                undoToast(undoLabel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let actionFeedback {
                feedbackToast(actionFeedback)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(DrawerTaskDestination.allCases, id: \.self) { choice in
                        Button {
                            destination = choice
                            DrawerHaptics.shared.progressChanged()
                        } label: {
                            Label(choice.title, systemImage: choice == destination ? "checkmark" : destinationIcon(choice))
                        }
                    }
                } label: {
                    Image(systemName: destinationIcon(destination))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 42, height: 42)
                        .background(.quaternary.opacity(0.5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(TactileButtonStyle())
                .accessibilityLabel("Add to \(destination.title)")

                TextField("Add to \(destination.title.lowercased())…", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .font(.body)
                    .onSubmit(save)

                Button(action: save) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white))
                        .frame(width: 38, height: 38)
                        .background(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AnyShapeStyle(.quaternary.opacity(0.7))
                                : AnyShapeStyle(Color.accentColor),
                            in: Circle()
                        )
                }
                .buttonStyle(TactileButtonStyle(pressedScale: 0.92))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add task")
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.primary.opacity(focused ? 0.12 : 0.055), lineWidth: focused ? 1 : 0.75)
            }
            .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(.clear)
        .onChange(of: model.captureRequestToken) { _, _ in
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .drawerActionFeedback)) { notification in
            guard let payload = notification.object as? DrawerActionFeedbackPayload else { return }
            actionFeedback = payload
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if actionFeedback?.id == payload.id {
                    actionFeedback = nil
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: model.undoLabel)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: actionFeedback?.id)
    }

    private func undoToast(_ label: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") {
                if model.undoLastMutation() {
                    DrawerHaptics.shared.undo()
                    DrawerActionFeedbackCenter.success("Undone", systemImage: "arrow.uturn.backward.circle.fill")
                }
            }
            .font(.footnote.weight(.bold))
        }
        .padding(.horizontal, 15)
        .frame(height: 44)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.primary.opacity(0.06), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .padding(.horizontal, 18)
    }

    private func feedbackToast(_ feedback: DrawerActionFeedbackPayload) -> some View {
        HStack(spacing: 9) {
            Image(systemName: feedback.systemImage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tint)
            Text(feedback.message)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(height: 44)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(.primary.opacity(0.06), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if model.add(clean, destination: destination) {
            text = ""
            DrawerHaptics.shared.taskAdded()
            DrawerActionFeedbackCenter.success(
                "Added to \(destination.title)",
                systemImage: "plus.circle.fill"
            )
            if !reduceMotion {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.65)) {
                    focused = false
                }
            } else {
                focused = false
            }
        }
    }

    private func destinationIcon(_ destination: DrawerTaskDestination) -> String {
        switch destination {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .backlog: "tray"
        }
    }
}
