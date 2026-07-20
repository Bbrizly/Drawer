import DrawerCore
import Foundation
import SwiftUI

/// The board page that slides in over the task list. A slim header with a back
/// chevron and a recenter button, then the fast canvas. Double-click a card to
/// edit its text inline; double-click empty space to make one. Right-click a
/// card for color and delete.
struct IdeaBoardPage: View {
    @ObservedObject var store: BoardStore
    var theme: DrawerTheme
    var lot: ParkingLotStore? = nil
    var onBack: () -> Void

    @Environment(SwipeCoordinator.self) private var swipe
    @State private var recenterRequests = 0
    @State private var lotZoom: CGFloat = 1
    @State private var showingBoardSelector = false
    // Board settings (see the Board tab in Settings).
    @AppStorage("boardBackground") private var boardBackground = "dark"
    @AppStorage("boardZoomStep") private var zoomStep = 1.25
    @AppStorage("feature.parkingLot") private var parkingLotEnabled = false
    @AppStorage("boardShowingParkingLot") private var showingLot = false

    private var transparent: Bool { boardBackground == "transparent" }
    private var paper: Bool { boardBackground == "paper" || theme == .notebook }
    private var xpBoard: Bool { theme.usesXPChrome && !transparent }
    private var lotActive: Bool { showingLot && parkingLotEnabled && lot != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            if lotActive, let lot {
                ParkingLotView(lot: lot, zoom: $lotZoom, resetRequests: recenterRequests)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BoardCanvas(
                    store: store,
                    recenterRequests: recenterRequests,
                    transparentBackground: transparent,
                    globalPanEnabled: swipe.showingBoard,
                    paperBackground: paper,
                    xpBackground: xpBoard
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            boardSelector
            Spacer()
            if !lotActive {
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
            } else {
                DrawerIconButton(
                    systemName: "minus.magnifyingglass",
                    accessibilityLabel: "Zoom out",
                    helpText: "Zoom out."
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lotZoom = max(0.5, lotZoom / CGFloat(zoomStep))
                    }
                }
                DrawerIconButton(
                    systemName: "plus.magnifyingglass",
                    accessibilityLabel: "Zoom in",
                    helpText: "Zoom in."
                ) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lotZoom = min(2.5, lotZoom * CGFloat(zoomStep))
                    }
                }
                DrawerIconButton(
                    systemName: "scope",
                    accessibilityLabel: "Reset view",
                    helpText: "Back to the original view."
                ) {
                    recenterRequests += 1
                }
            }
            Text(lotActive ? "\(lot?.ideaCount ?? 0)" : "\(store.document.items.count)")
                .font(theme.usesXPChrome
                      ? FontLoader.xpFont(size: 11, weight: .semibold)
                      : .system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    theme.usesXPChrome
                        ? AnyShapeStyle(Color.white.opacity(0.85))
                        : AnyShapeStyle(.tertiary)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if theme.usesXPChrome {
                LinearGradient(
                    colors: [Palette.xpTitleTop, Palette.xpTitleBottom],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .environment(\.xpOnDarkChrome, theme.usesXPChrome)
        .contentShape(Rectangle())
        // Hovering this bar arms the swipe-back gesture (see ScrollSwipeMonitor).
        .onHover { swipe.pointerOverChrome = $0 }
    }

    private var boardSelector: some View {
        Button {
            showingBoardSelector.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(lotActive ? "Parking lot" : store.activeBoardName)
                    .font(theme.usesXPChrome
                          ? FontLoader.xpFont(size: 14, weight: .bold)
                          : .system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.usesXPChrome
                                     ? AnyShapeStyle(Color.white.opacity(0.9))
                                     : AnyShapeStyle(.tertiary))
            }
            .foregroundStyle(theme.usesXPChrome ? Color.white : theme.primaryInk)
            .frame(maxWidth: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select board")
        .help("Select board")
        .popover(isPresented: $showingBoardSelector, arrowEdge: .bottom) {
            BoardSelectorPopover(
                store: store,
                lot: parkingLotEnabled ? lot : nil,
                showingLot: $showingLot,
                isPresented: $showingBoardSelector
            )
            .environment(\.drawerTheme, theme)
        }
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

private struct BoardSelectorPopover: View {
    @ObservedObject var store: BoardStore
    var lot: ParkingLotStore?
    @Binding var showingLot: Bool
    @Binding var isPresented: Bool
    @Environment(\.drawerTheme) private var theme
    @State private var editingBoardID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let lot {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(showingLot ? 1 : 0)
                        .frame(width: 14)
                    Image(systemName: "car.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Parking lot")
                        .font(theme.uiFont(size: 13, weight: showingLot ? .semibold : .regular))
                    Spacer()
                    Text("\(lot.ideaCount)")
                        .font(theme.uiFont(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingLot = true
                    isPresented = false
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Parking lot, \(lot.ideaCount) ideas")
                .accessibilityAddTraits(showingLot ? [.isButton, .isSelected] : .isButton)
                Divider()
            }
            List {
                ForEach(store.document.boards) { board in
                    BoardSelectorRow(
                        board: board,
                        selected: board.id == store.document.activeBoardID && !showingLot
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectBoard(board.id)
                        showingLot = false
                        isPresented = false
                    }
                    .popover(
                        isPresented: editBinding(for: board.id),
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .trailing
                    ) {
                        BoardEditPopover(
                            store: store,
                            board: board,
                            renameDraft: $renameDraft,
                            isPresented: editBinding(for: board.id)
                        )
                        .environment(\.drawerTheme, theme)
                    }
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: store.document.boards.count > 1
                    ) {
                        if store.document.boards.count > 1 {
                            Button(role: .destructive) {
                                if editingBoardID == board.id { editingBoardID = nil }
                                store.removeBoard(board.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        Button {
                            renameDraft = board.name
                            editingBoardID = board.id
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(theme.accent)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(height: listHeight)

            Divider()

            Button {
                store.addBoard()
                isPresented = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add board")
            .help("Add board")
        }
        .frame(width: 280)
        .padding(6)
        .background(PanelBackground(theme: theme))
        .foregroundStyle(theme.primaryInk)
        .environment(\.colorScheme, theme.popoverColorScheme)
    }

    private var listHeight: CGFloat {
        min(max(CGFloat(store.document.boards.count) * 38, 38), 228)
    }

    private func editBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { editingBoardID == id },
            set: { showing in
                if showing {
                    editingBoardID = id
                } else if editingBoardID == id {
                    editingBoardID = nil
                }
            }
        )
    }
}

private struct BoardSelectorRow: View {
    let board: BoardRecord
    let selected: Bool
    @Environment(\.drawerTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .opacity(selected ? 1 : 0)
                .frame(width: 14)
            Text(board.name)
                .font(theme.uiFont(size: 13, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text("\(board.items.count)")
                .font(theme.uiFont(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(board.name), \(board.items.count) items")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct BoardEditPopover: View {
    @ObservedObject var store: BoardStore
    let board: BoardRecord
    @Binding var renameDraft: String
    @Binding var isPresented: Bool
    @Environment(\.drawerTheme) private var theme
    @FocusState private var nameFocused: Bool

    private var metrics: BoardMetrics { store.metrics(for: board) }
    private var trimmedName: String {
        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Board name", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(rename)
                Button(action: rename) {
                    Label("Rename", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty || trimmedName == board.name)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                metricRow("Items", "\(metrics.itemCount)")
                metricRow("Text", "\(metrics.textCount)")
                metricRow("Images", "\(metrics.imageCount)")
                metricRow("Storage", bytes(metrics.totalBytes))
                metricRow("JSON", bytes(metrics.jsonBytes))
                metricRow("Media", bytes(metrics.mediaBytes))
                metricRow("Render load", "\(metrics.canvasLoadPercent)% of smooth budget")
                metricRow("Layer budget", "\(metrics.canvasLayerCount)/\(BoardMetrics.smoothLayerBudget)")
                metricRow("Draw area", "\(number(metrics.canvasPointArea))/\(number(BoardMetrics.smoothAreaBudget)) pt^2")
                metricRow("Zoom", "\(Int(board.viewport.zoom * 100))%")
            }
        }
        .padding(12)
        .frame(width: 270)
        .background(PanelBackground(theme: theme))
        .foregroundStyle(theme.primaryInk)
        .environment(\.colorScheme, theme.popoverColorScheme)
        .onAppear {
            renameDraft = board.name
            nameFocused = true
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(theme.secondaryInk)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(theme.primaryInk)
        }
        .font(theme.uiFont(size: 12))
    }

    private func rename() {
        store.renameBoard(board.id, to: renameDraft)
        isPresented = false
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func number(_ count: Int) -> String {
        count.formatted(.number)
    }
}
