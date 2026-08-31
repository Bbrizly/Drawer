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
        HStack(alignment: .top, spacing: 8) {
            checkbox

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(item.isInProgress ? .semibold : .regular))
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .strikethrough(item.isDone, color: .secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.minutes != 25 && !item.isDone {
                        Text("\(item.minutes)m")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if let note = item.note, !note.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "text.alignleft")
                            .font(.caption2.weight(.bold))
                        Text(note.replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 1)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.quaternary)
                .frame(width: 15, height: 24)
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 60)
        .background {
            ZStack(alignment: .leading) {
                Color(uiColor: .secondarySystemGroupedBackground).opacity(0.82)
                if item.isInProgress && !item.isDone {
                    Color.accentColor.opacity(0.075)
                    Rectangle()
                        .fill(.tint)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openTask)
        .opacity(item.isDone ? 0.68 : 1)
    }

    private var checkbox: some View {
        Button(action: checkboxTapped) {
            Image(systemName: checkboxSymbol)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    item.isDone || item.isInProgress
                        ? AnyShapeStyle(.tint)
                        : AnyShapeStyle(.tertiary)
                )
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .scaleEffect(checkboxScale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isDone ? "Reopen task" : "Complete task")
        .accessibilityValue(item.title)
    }

    private var checkboxSymbol: String {
        if item.isDone { return "checkmark.circle.fill" }
        if item.isInProgress { return "circle.lefthalf.filled" }
        return "circle"
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
        }

        Menu("Move", systemImage: "arrow.turn.down.right") {
            moveButton(.today)
            moveButton(.tomorrow)
            moveButton(.backlog)
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
