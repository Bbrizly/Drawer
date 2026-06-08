import DrawerCore
import SwiftUI

struct TaskRowView: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore
    @Environment(\.drawerTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCheckboxHovering = false
    @State private var isRowHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                if reduceMotion {
                    store.toggle(item)
                } else {
                    withAnimation(.snappy(duration: 0.25)) { store.toggle(item) }
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: theme.checkboxSize, weight: .medium))
                    .foregroundStyle(
                        item.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 24)
                    .background(
                        isCheckboxHovering ? Color.secondary.opacity(0.10) : Color.clear,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark task incomplete" : "Complete task")
            .accessibilityValue(item.title)
            .accessibilityHint("Update this task in the markdown file.")
            .help(item.isDone ? "Mark incomplete" : "Mark complete")
            .onHover { isCheckboxHovering = $0 }

            Text(item.title)
                .font(.callout)
                .lineSpacing(2)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true) // wrap, never truncate

            Spacer(minLength: 0)

            if item.minutes != 25 && !item.isDone {
                Text("\(item.minutes)m")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.8), in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, theme.rowVerticalPadding)
        .background(
            isRowHovering ? Color.primary.opacity(0.055) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) {
            if theme.showsRowSeparators {
                Divider().opacity(0.4).padding(.leading, 40)
            }
        }
        .onHover { isRowHovering = $0 }
    }
}
