import DrawerCore
import SwiftUI

/// The board page that slides in over the task list. A slim header with a back
/// chevron and a recenter button, then the fast canvas. Double-click a card to
/// edit its text inline; double-click empty space to make one. Right-click a
/// card for color and delete.
struct IdeaBoardPage: View {
    @ObservedObject var store: BoardStore
    var theme: DrawerTheme
    var onBack: () -> Void

    @Environment(SwipeCoordinator.self) private var swipe
    @State private var recenterRequests = 0
    // Board settings (see the Board tab in Settings).
    @AppStorage("boardBackground") private var boardBackground = "dark"
    @AppStorage("boardDefaultColor") private var defaultColor = "yellow"
    @AppStorage("boardZoomStep") private var zoomStep = 1.25

    private var transparent: Bool { boardBackground == "transparent" }
    private var paper: Bool { boardBackground == "paper" || theme == .notebook }

    var body: some View {
        VStack(spacing: 0) {
            header
            BoardCanvas(
                store: store,
                recenterRequests: recenterRequests,
                transparentBackground: transparent,
                globalPanEnabled: swipe.showingBoard,
                paperBackground: paper,
                defaultCardColor: defaultColor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Transparent: a 1% tint instead of the glass plate, so the desktop shows
        // through but the window still catches events (no fall-through on alpha 0).
        .background {
            if transparent {
                Palette.hitClear.color
            } else {
                PanelBackground(theme: theme)
            }
        }
        .environment(\.controlActiveState, .active)
    }

    private var header: some View {
        HStack(spacing: 8) {
            DrawerIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back to tasks",
                helpText: "Return to your task list."
            ) {
                onBack()
            }
            Text("Ideas")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            DrawerIconButton(
                systemName: "arrow.uturn.backward",
                accessibilityLabel: "Undo",
                helpText: "Undo the last board change."
            ) {
                store.undo()
            }
            DrawerIconButton(
                systemName: "arrow.uturn.forward",
                accessibilityLabel: "Redo",
                helpText: "Redo the last undone change."
            ) {
                store.redo()
            }
            DrawerIconButton(
                systemName: "minus.magnifyingglass",
                accessibilityLabel: "Zoom out",
                helpText: "Zoom out."
            ) {
                store.zoomBy(CGFloat(1 / zoomStep))
            }
            DrawerIconButton(
                systemName: "plus.magnifyingglass",
                accessibilityLabel: "Zoom in",
                helpText: "Zoom in."
            ) {
                store.zoomBy(CGFloat(zoomStep))
            }
            DrawerIconButton(
                systemName: "scope",
                accessibilityLabel: "Recenter board",
                helpText: "Center the view on your cards."
            ) {
                recenterRequests += 1
            }
            DrawerIconButton(
                systemName: backgroundIcon,
                accessibilityLabel: "Board background",
                helpText: "Cycle the background: dark, transparent, paper.",
                isSelected: boardBackground != "dark"
            ) {
                cycleBackground()
            }
            Text("\(store.document.items.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Hovering this bar arms the swipe-back gesture (see ScrollSwipeMonitor).
        .onHover { swipe.pointerOverChrome = $0 }
    }

    private var backgroundIcon: String {
        switch boardBackground {
        case "transparent": return "square.dashed"
        case "paper": return "doc.plaintext"
        default: return "square.fill"
        }
    }

    private func cycleBackground() {
        switch boardBackground {
        case "dark": boardBackground = "transparent"
        case "transparent": boardBackground = "paper"
        default: boardBackground = "dark"
        }
    }
}
