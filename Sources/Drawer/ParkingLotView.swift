import AppKit
import DrawerCore
import SwiftUI

/// The lot: bays from the markdown as blocks of painted stalls, one car per
/// stall in file order. Every block paints a full column of lines, so the lot
/// looks like a lot even where no car is parked; tapping an empty stall parks
/// a fresh idea in that bay. A bay overflows into the next block right; blocks
/// alternate the way they nose in so each faces the bare gap on its own side.
/// There is no road. Zoom magnifies, nothing else.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore
    @Binding var zoom: CGFloat
    var resetRequests: Int

    @State private var gestureZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var lotFrame: CGRect = .zero
    @State private var scrollMonitor: Any?
    @State private var selected: IdeaRef?
    @Namespace private var carSpace

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int
    }

    private let stallWidth: CGFloat = 168
    private let stallHeight: CGFloat = 108
    private let gapWidth: CGFloat = 56
    private let openGapWidth: CGFloat = 460
    private let asphalt = Color(red: 0.165, green: 0.165, blue: 0.18)
    private let paint = Color.white.opacity(0.16)
    private let stencilInk = Color.white.opacity(0.5)

    private struct Block: Identifiable {
        var id: Int
        var bay: Int
        var range: Range<Int>
        var showsLabel: Bool
        /// Odd blocks mirror so their cars nose left, into the shared gap.
        var mirrored: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let stallsPerColumn = max(1, Int((geo.size.height - 80) / stallHeight))
            ZStack(alignment: .topLeading) {
                lotBody(stallsPerColumn: stallsPerColumn)
                    .padding(24)
                    .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
                    .offset(
                        x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(asphalt)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { gestureZoom = $0.magnification }
                    .onEnded { _ in
                        zoom = min(2.5, max(0.5, zoom * gestureZoom))
                        gestureZoom = 1
                    }
            )
            .onChange(of: resetRequests) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    zoom = 1
                    offset = .zero
                }
            }
            .onAppear {
                lotFrame = geo.frame(in: .global)
                installScrollMonitor()
            }
            .onChange(of: geo.frame(in: .global)) { _, frame in
                lotFrame = frame
            }
            .onDisappear { removeScrollMonitor() }
        }
    }

    /// Two-finger scroll pans the lot, the same way it scrolls anything else.
    /// The panel's text editor sits in its own scroll view, so events over it
    /// pass through and scroll the text instead.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let content = event.window?.contentView else { return event }
            if let hit = content.hitTest(event.locationInWindow),
               hit.enclosingScrollView != nil {
                return event
            }
            let point = CGPoint(
                x: event.locationInWindow.x,
                y: content.bounds.height - event.locationInWindow.y)
            guard lotFrame.contains(point) else { return event }
            var dx = event.scrollingDeltaX
            var dy = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                dx *= 8
                dy *= 8
            }
            offset.width += dx
            offset.height += dy
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private func blocks(stallsPerColumn: Int) -> [Block] {
        var out: [Block] = []
        for (b, bay) in lot.document.bays.enumerated() {
            let cols = ParkingLotLayout.columns(bay.ideas.count, stallsPerColumn: stallsPerColumn)
            for (i, range) in cols.enumerated() {
                out.append(Block(
                    id: out.count, bay: b, range: range,
                    showsLabel: i == 0, mirrored: out.count % 2 == 1))
            }
            // Every bay keeps at least one empty painted stall to park into,
            // so a full (or emptied) bay grows a fresh column of spaces.
            if bay.ideas.count % stallsPerColumn == 0 {
                let count = bay.ideas.count
                out.append(Block(
                    id: out.count, bay: b, range: count..<count,
                    showsLabel: cols.isEmpty, mirrored: out.count % 2 == 1))
            }
        }
        return out
    }

    @ViewBuilder
    private func lotBody(stallsPerColumn: Int) -> some View {
        if lot.document.bays.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                bayLabel("UNSORTED")
                ForEach(0..<stallsPerColumn, id: \.self) { _ in
                    EmptyStall(
                        width: stallWidth, height: stallHeight,
                        paint: paint, mirrored: false
                    ) {
                        addIdea(toBay: "Unsorted")
                    }
                }
            }
        } else {
            let blocks = blocks(stallsPerColumn: stallsPerColumn)
            let openGap = selectedGapIndex(in: blocks)
            HStack(alignment: .top, spacing: 0) {
                ForEach(blocks) { block in
                    blockView(block, stallsPerColumn: stallsPerColumn)
                    gapView(index: block.id, open: openGap == block.id, blocks: blocks)
                }
            }
            .animation(.easeOut(duration: 0.3), value: selected)
            .onExitCommand { close() }
        }
    }

    private func blockContaining(_ ref: IdeaRef, in blocks: [Block]) -> Block? {
        blocks.first { $0.bay == ref.bay && $0.range.contains(ref.idea) }
    }

    private func selectedGapIndex(in blocks: [Block]) -> Int? {
        guard let sel = selected, let block = blockContaining(sel, in: blocks) else { return nil }
        return block.mirrored ? block.id - 1 : block.id
    }

    private func bayLabel(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .kerning(2)
            .foregroundStyle(.white.opacity(0.4))
            .frame(height: 18)
            .padding(.bottom, 8)
    }

    private func blockView(_ block: Block, stallsPerColumn: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            bayLabel(block.showsLabel ? lot.document.bays[block.bay].name.uppercased() : " ")
            ForEach(block.range, id: \.self) { i in
                stall(bay: block.bay, idea: i, mirrored: block.mirrored)
            }
            // The painted lines exist before the cars do: fill the column out
            // with empty spaces, each one a tap target for a new idea.
            ForEach(0..<max(0, stallsPerColumn - block.range.count), id: \.self) { _ in
                EmptyStall(
                    width: stallWidth, height: stallHeight,
                    paint: paint, mirrored: block.mirrored
                ) {
                    addIdea(toBay: lot.document.bays[block.bay].name)
                }
            }
        }
    }

    private func addIdea(toBay name: String) {
        if selected != nil { close() }
        lot.park(title: "", details: "", toBay: name)
        guard let b = lot.document.bays.firstIndex(where: { $0.name == name }),
              !lot.document.bays[b].ideas.isEmpty else { return }
        selected = IdeaRef(bay: b, idea: lot.document.bays[b].ideas.count - 1)
    }

    private func stall(bay: Int, idea: Int, mirrored: Bool) -> some View {
        let ref = IdeaRef(bay: bay, idea: idea)
        let parked = lot.document.bays[bay].ideas[idea]
        let out = selected == ref
        return VStack(spacing: 5) {
            if out {
                // The car is out in the gap; keep its footprint.
                Color.clear
                    .frame(width: stallWidth - 28, height: (stallWidth - 28) * 128 / 300)
            } else {
                CarSprite(color: Palette.card(parked.color).color)
                    .frame(width: stallWidth - 28)
                    .scaleEffect(x: mirrored ? -1 : 1)
                    .matchedGeometryEffect(id: ref, in: carSpace)
            }
            Text(parked.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk.opacity(out ? 0.6 : 1))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 28)
        }
        .frame(width: stallWidth, height: stallHeight)
        // The whole stall is the target, stencil included, not just the car.
        .contentShape(Rectangle())
        .onTapGesture { toggle(ref) }
        .overlay(StallLines(paint: paint, mirrored: mirrored))
    }

    private func gapView(index: Int, open: Bool, blocks: [Block]) -> some View {
        Group {
            if open, let sel = selected, let parked = idea(sel),
               let block = blockContaining(sel, in: blocks) {
                VStack(alignment: .leading, spacing: 12) {
                    CarSprite(color: Palette.card(parked.color).color)
                        .frame(width: stallWidth - 28)
                        .scaleEffect(x: block.mirrored ? -1 : 1)
                        .matchedGeometryEffect(id: sel, in: carSpace)
                        .onTapGesture { close() }
                    IdeaPanel(
                        lot: lot, bay: sel.bay, idea: sel.idea,
                        onMoveToBay: { target in moveSelected(toBay: target) },
                        onClose: { close() })
                        .id(sel)
                        .frame(width: 400)
                }
                .padding(.top, 26 + CGFloat(sel.idea - block.range.lowerBound) * stallHeight)
                .padding(.horizontal, 24)
                .frame(width: openGapWidth, alignment: .topLeading)
            } else {
                Color.clear.frame(width: gapWidth, height: 1)
            }
        }
    }

    private func idea(_ ref: IdeaRef) -> ParkedIdea? {
        guard lot.document.bays.indices.contains(ref.bay),
              lot.document.bays[ref.bay].ideas.indices.contains(ref.idea) else { return nil }
        return lot.document.bays[ref.bay].ideas[ref.idea]
    }

    private func toggle(_ ref: IdeaRef) {
        if selected == ref {
            close()
        } else {
            if selected != nil { close() }
            selected = ref
        }
    }

    /// Reverses the car back in. An idea cleared to nothing is removed, no
    /// confirmation: closing an empty panel is the delete gesture.
    private func close() {
        guard let sel = selected else { return }
        if let parked = idea(sel), parked.title.isEmpty, parked.details.isEmpty {
            lot.delete(bayIndex: sel.bay, ideaIndex: sel.idea)
        }
        lot.saveNow()
        selected = nil
    }

    private func moveSelected(toBay target: String) {
        guard let sel = selected else { return }
        lot.move(bayIndex: sel.bay, ideaIndex: sel.idea, toBay: target)
        if let b = lot.document.bays.firstIndex(where: { $0.name == target }),
           !lot.document.bays[b].ideas.isEmpty {
            selected = IdeaRef(bay: b, idea: lot.document.bays[b].ideas.count - 1)
        } else {
            selected = nil
        }
    }
}

/// Painted stall lines: top, bottom, and the closed end. The open end
/// faces the gap the car noses into.
private struct StallLines: View {
    let paint: Color
    let mirrored: Bool

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width
                let h = geo.size.height
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: w, y: 0))
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
                let closedX: CGFloat = mirrored ? w : 0
                p.move(to: CGPoint(x: closedX, y: 0))
                p.addLine(to: CGPoint(x: closedX, y: h))
            }
            .stroke(paint, lineWidth: 2)
        }
    }
}

/// A painted space with no car in it. Hover shows a faint plus; a tap parks a
/// fresh idea there, and closing the panel without typing removes it again.
private struct EmptyStall: View {
    let width: CGFloat
    let height: CGFloat
    let paint: Color
    let mirrored: Bool
    var onPark: () -> Void

    @State private var hovered = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(hovered ? 0.35 : 0))
            .frame(width: width, height: height)
            .background(Color.white.opacity(hovered ? 0.03 : 0))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { onPark() }
            .overlay(StallLines(paint: paint, mirrored: mirrored))
            .help("Park a new idea here")
    }
}

/// The pulled-out idea. The panel is the markdown, not a form: the first line
/// is the title, the rest is the details. No save button; edits splice back
/// through the store's debounce. The caret lands on open.
private struct IdeaPanel: View {
    @ObservedObject var lot: ParkingLotStore
    let bay: Int
    let idea: Int
    var onMoveToBay: (String) -> Void
    var onClose: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    /// Panel swatches in a fixed order; the parser's set has none.
    private static let colorKeys = ["yellow", "pink", "blue", "green", "purple", "gray"]

    init(
        lot: ParkingLotStore, bay: Int, idea: Int,
        onMoveToBay: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self._lot = ObservedObject(wrappedValue: lot)
        self.bay = bay
        self.idea = idea
        self.onMoveToBay = onMoveToBay
        self.onClose = onClose
        let parked = lot.document.bays[bay].ideas[idea]
        self._draft = State(initialValue: parked.details.isEmpty
            ? parked.title
            : parked.title + "\n" + parked.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaLine
            TextEditor(text: $draft)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14))
                .lineSpacing(2)
                .frame(minHeight: 180, maxHeight: 400)
                // The text view eats Escape for completions, so onExitCommand
                // never fires while typing. Catch the key itself.
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
            colorRow
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.957, green: 0.945, blue: 0.91)))
        .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 5)
        .onAppear { focused = true }
        .onChange(of: draft) { _, text in
            let parts = split(text)
            lot.update(
                bayIndex: bay, ideaIndex: idea,
                title: parts.title, details: parts.details, color: currentColor)
        }
    }

    private var currentColor: String? {
        guard lot.document.bays.indices.contains(bay),
              lot.document.bays[bay].ideas.indices.contains(idea) else { return nil }
        return lot.document.bays[bay].ideas[idea].color
    }

    private func split(_ text: String) -> (title: String, details: String) {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return (
            String(parts.first ?? "").trimmingCharacters(in: .whitespaces),
            parts.count > 1 ? String(parts[1]) : "")
    }

    private var colorRow: some View {
        HStack(spacing: 8) {
            ForEach(Self.colorKeys, id: \.self) { key in
                let active = key == (currentColor ?? "yellow")
                Circle()
                    .fill(Palette.card(key).color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(
                        Color.black.opacity(active ? 0.55 : 0.12),
                        lineWidth: active ? 2 : 1))
                    .contentShape(Circle())
                    .onTapGesture {
                        let parts = split(draft)
                        lot.update(
                            bayIndex: bay, ideaIndex: idea,
                            title: parts.title, details: parts.details, color: key)
                    }
                    .help(key.capitalized)
            }
            Spacer()
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let parked = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].parked : nil {
                Text("PARKED \(parked)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(lot.document.bays.map(\.name), id: \.self) { name in
                    Button(name) {
                        if name != lot.document.bays[bay].name { onMoveToBay(name) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(lot.document.bays.indices.contains(bay)
                        ? lot.document.bays[bay].name : "")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
