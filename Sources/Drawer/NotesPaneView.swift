import AppKit
import DrawerCore
import SwiftUI

/// The scratchpad that drops into the header. One always-there note that saves
/// itself as you type. A drag handle at the bottom sets its height, and the
/// button up top throws the text onto the teleprompter.
struct NotesPaneView: View {
    @ObservedObject var notes: NotesStore
    @Binding var height: Double
    var onToggleTeleprompter: () -> Void
    var onNeedsKeyboard: () -> Void

    @Environment(\.drawerTheme) private var theme
    @State private var dragBase: Double?

    private let minHeight: Double = 90
    private let maxHeight: Double = 460

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onToggleTeleprompter) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help("Open teleprompter: scroll these notes at the top of the screen.")
                .accessibilityLabel("Open teleprompter")
            }
            .padding(.horizontal, 11)
            .padding(.top, 8)
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
