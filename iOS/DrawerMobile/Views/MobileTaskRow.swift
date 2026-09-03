import DrawerCore
import SwiftUI

struct MobileTaskRow: View {
    @ObservedObject var model: DrawerMobileModel
    let item: TodoItem
    let openTask: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var dragAxis: DragAxis?
    @State private var armedAction: ArmedAction = .none
    @State private var checkboxScale: CGFloat = 1

    private enum DragAxis { case horizontal, vertical }
    private enum ArmedAction { case none, primary, delete }

    private let primaryThreshold: CGFloat = 72
    private let deleteThreshold: CGFloat = 108

    var body: some View {
        ZStack {
            swipeReveals
            rowContent
                .offset(x: dragOffset)
        }
        .contentShape(Rectangle())
        .gesture(swipeGesture, including: .all)
        .contextMenu { contextMenu }
        .accessibilityAction(named: primaryAccessibilityAction) {
            performPrimaryAction()
        }
        .accessibilityAction(named: "Delete") {
            if model.delete(item) { DrawerHaptics.shared.deleted() }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 13) {
            checkbox

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.system(.body, design: .default, weight: item.isInProgress ? .semibold : .regular))
                        .foregroundStyle(item.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(DrawerPalette.ink))
                        .strikethrough(item.isDone, color: .secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.minutes != 25 && !item.isDone {
                        Text("\(item.minutes)m")
                            .font(.caption2.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(DrawerPalette.accent)
                    }
                }

                if let note = item.note, !note.isEmpty {
                    Text(note.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, item.note == nil || item.note?.isEmpty == true ? 12 : 14)
        .frame(minHeight: item.note == nil || item.note?.isEmpty == true ? 56 : 72)
        .contentShape(Rectangle())
        .onTapGesture(perform: openTask)
        .opacity(item.isDone ? 0.55 : 1)
    }

    private var checkbox: some View {
        Button(action: checkboxTapped) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(item.isDone || item.isInProgress ? DrawerPalette.accent : .secondary.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 22, height: 22)

                if item.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(DrawerPalette.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if item.isInProgress {
                    Circle()
                        .fill(DrawerPalette.accent)
                        .frame(width: 8, height: 8)
                }
            }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .scaleEffect(checkboxScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Reopen task" : "Complete task")
        .accessibilityValue(item.title)
    }

    private var primaryAccessibilityAction: String {
        if item.isDone { return "Reopen" }
        return item.isInProgress ? "Clear in progress" : "Mark in progress"
    }

    private var swipeReveals: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: leadingActionIcon)
                    .font(.system(size: 17, weight: .bold))
                Text(leadingActionTitle)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.leading, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.tint)

            HStack(spacing: 8) {
                Text("Delete")
                    .font(.caption.weight(.bold))
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .background(Color.red)
        }
        .accessibilityHidden(true)
    }

    private var leadingActionTitle: String {
        if item.isDone { return "Reopen" }
        return item.isInProgress ? "Clear" : "Doing"
    }

    private var leadingActionIcon: String {
        if item.isDone { return "arrow.uturn.backward" }
        return item.isInProgress ? "circle" : "circle.lefthalf.filled"
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal : .vertical
                    if dragAxis == .horizontal {
                        DrawerHaptics.shared.prepareForSwipe()
                    }
                }
                guard dragAxis == .horizontal else { return }

                dragOffset = resisted(value.translation.width)
                let next = armedAction(for: dragOffset)
                if next != armedAction {
                    if next == .primary {
                        DrawerHaptics.shared.swipeThreshold()
                    } else if next == .delete {
                        DrawerHaptics.shared.destructiveArmed()
                    }
                    armedAction = next
                }
            }
            .onEnded { value in
                defer {
                    dragAxis = nil
                    armedAction = .none
                    if reduceMotion {
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                            dragOffset = 0
                        }
                    }
                }
                guard dragAxis == .horizontal else { return }

                let projected = value.predictedEndTranslation.width
                let commitsDelete = dragOffset <= -deleteThreshold || projected <= -180
                let commitsPrimary = dragOffset >= primaryThreshold || projected >= 145

                if commitsDelete {
                    if model.delete(item) { DrawerHaptics.shared.deleted() }
                } else if commitsPrimary {
                    performPrimaryAction()
                }
            }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if item.isDone {
            Button("Reopen", systemImage: "arrow.uturn.backward") {
                reopenTask()
            }
        } else {
            Button(item.isInProgress ? "Clear In Progress" : "Mark In Progress", systemImage: "circle.lefthalf.filled") {
                changeProgress()
            }
            Button("Start Focus", systemImage: "timer") {
                model.startFocus(on: item)
                DrawerHaptics.shared.focusStarted()
            }
            Menu("Move", systemImage: "arrow.turn.down.right") {
                moveButton(.today)
                moveButton(.tomorrow)
                moveButton(.backlog)
            }
        }

        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if model.delete(item) { DrawerHaptics.shared.deleted() }
        }
    }

    private func moveButton(_ destination: DrawerTaskDestination) -> some View {
        Button(destination.title) {
            if model.move(item, to: destination) {
                DrawerHaptics.shared.moved()
            }
        }
    }

    private func performPrimaryAction() {
        if item.isDone {
            reopenTask()
        } else {
            changeProgress()
        }
    }

    private func changeProgress() {
        if model.setInProgress(item, !item.isInProgress) {
            DrawerHaptics.shared.progressChanged()
            confirmProgressChange()
        }
    }

    private func reopenTask() {
        if model.toggle(item) {
            DrawerHaptics.shared.taskReopened()
            DrawerActionFeedbackCenter.success(
                "Reopened \(item.title)",
                systemImage: "arrow.uturn.backward.circle.fill"
            )
        }
    }

    private func checkboxTapped() {
        let willComplete = !item.isDone
        if !reduceMotion {
            withAnimation(.spring(response: 0.10, dampingFraction: 0.72)) {
                checkboxScale = 0.78
            }
        }

        let perform = {
            let success = model.toggle(item)
            if success {
                if willComplete {
                    DrawerHaptics.shared.taskCompleted()
                    DrawerActionFeedbackCenter.success(
                        "Completed \(item.title)",
                        systemImage: "checkmark.circle.fill"
                    )
                } else {
                    DrawerHaptics.shared.taskReopened()
                    DrawerActionFeedbackCenter.success(
                        "Reopened \(item.title)",
                        systemImage: "arrow.uturn.backward.circle.fill"
                    )
                }
            }
            if !reduceMotion {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.64)) {
                    checkboxScale = 1
                }
            } else {
                checkboxScale = 1
            }
        }

        if reduceMotion {
            perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035, execute: perform)
        }
    }

    private func confirmProgressChange() {
        DrawerActionFeedbackCenter.success(
            item.isInProgress ? "Cleared in progress" : "Marked in progress",
            systemImage: item.isInProgress ? "circle" : "circle.lefthalf.filled"
        )
    }

    private func armedAction(for offset: CGFloat) -> ArmedAction {
        if offset >= primaryThreshold { return .primary }
        if offset <= -deleteThreshold { return .delete }
        return .none
    }

    private func resisted(_ raw: CGFloat) -> CGFloat {
        let limit: CGFloat = 118
        let magnitude = abs(raw)
        guard magnitude > limit else { return raw }
        let excess = magnitude - limit
        let resisted = limit + excess * 0.22
        return raw.sign == .minus ? -resisted : resisted
    }
}
