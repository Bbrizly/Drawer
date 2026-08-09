import AppKit
import DrawerCore
import SwiftUI

/// The scratchpad that drops into the header. Notes save themselves as you
/// type. A row of small tabs across the top swaps between note files, a drag
/// handle at the bottom sets the height, and the button up top throws the
/// text onto the teleprompter.
struct NotesPaneView: View {
    @ObservedObject var notes: NotesStore
    @Binding var height: Double
    var onToggleTeleprompter: () -> Void
    var onNeedsKeyboard: () -> Void

    @Environment(\.drawerTheme) private var theme
    @Environment(SwipeCoordinator.self) private var swipe
    @State private var dragBase: Double?

    private let minHeight: Double = 90
    private let maxHeight: Double = 460

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                tabStrip
                Spacer(minLength: 4)
                Button(action: onToggleTeleprompter) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("Open teleprompter: scroll these notes at the top of the screen.")
                .accessibilityLabel("Open teleprompter")
            }
            .padding(.horizontal, 9)
            .padding(.top, 6)
            .padding(.bottom, 4)

            TextEditor(text: $notes.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .frame(height: height)
                .onTapGesture { onNeedsKeyboard() }

            resizeHandle
        }
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Small, quiet, and scrollable sideways so twenty notes still fit in a
    /// 400pt panel. The plus adds a file; the x on the open tab closes it,
    /// which files it away rather than deleting anything.
    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(notes.tabs.enumerated()), id: \.element.id) { index, tab in
                    NoteTabChip(
                        label: tab.label,
                        active: index == notes.activeIndex,
                        closeable: index > 0 && index == notes.activeIndex,
                        accent: theme.accent,
                        onOpen: {
                            notes.select(index)
                            onNeedsKeyboard()
                        },
                        onClose: { notes.removeTab(at: index) }
                    )
                }
                Button {
                    notes.addTab()
                    onNeedsKeyboard()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 17)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New note")
                .accessibilityLabel("New note")
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Sideways swipes here scroll the tabs, they don't page to the board.
        .onHover { swipe.pointerOverSideScroller = $0 }
        .onDisappear { swipe.pointerOverSideScroller = false }
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(.secondary.opacity(dragBase == nil ? 0.35 : 0.6))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 18) // tall, full-width grab zone so it is easy to catch
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = dragBase ?? height
                        if dragBase == nil { dragBase = height }
                        height = min(max(base + value.translation.height, minHeight), maxHeight)
                    }
                    .onEnded { _ in dragBase = nil }
            )
            .help("Drag to resize the notes pad")
    }
}

/// One tab. A bookmark, not a button: no border until it is the open one.
private struct NoteTabChip: View {
    let label: String
    let active: Bool
    let closeable: Bool
    let accent: Color
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            if closeable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 11, height: 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close this note. The file is kept, in Drawer Notes/Removed.")
                .accessibilityLabel("Close note")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 17)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accent.opacity(active ? 0.16 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}
