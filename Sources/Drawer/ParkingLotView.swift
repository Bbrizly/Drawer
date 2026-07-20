import DrawerCore
import SwiftUI

/// The lot: bays from the markdown as blocks of painted stalls, one car per
/// stall in file order. A bay overflows into the next block right; blocks
/// alternate the way they nose in so each faces the bare gap on its own side.
/// There is no road. Zoom magnifies, nothing else.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @State private var selected: IdeaRef?
    @Namespace private var carSpace

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int
    }

    private let stallWidth: CGFloat = 168
    private let stallHeight: CGFloat = 108
    private let gapWidth: CGFloat = 56
    private let openGapWidth: CGFloat = 300
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
            ScrollView([.horizontal, .vertical]) {
                lotBody(stallsPerColumn: stallsPerColumn)
                    .padding(24)
                    .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
            }
            .background(asphalt)
            .gesture(
                MagnifyGesture()
                    .onChanged { gestureZoom = $0.magnification }
                    .onEnded { _ in
                        zoom = min(2.5, max(0.5, zoom * gestureZoom))
                        gestureZoom = 1
                    }
            )
        }
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
        }
        return out
    }

    private func lotBody(stallsPerColumn: Int) -> some View {
        let blocks = blocks(stallsPerColumn: stallsPerColumn)
        let openGap = selectedGapIndex(in: blocks)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(blocks) { block in
                blockView(block)
                gapView(index: block.id, open: openGap == block.id, blocks: blocks)
            }
        }
        .animation(.easeOut(duration: 0.3), value: selected)
        .onExitCommand { close() }
    }

    private func blockContaining(_ ref: IdeaRef, in blocks: [Block]) -> Block? {
        blocks.first { $0.bay == ref.bay && $0.range.contains(ref.idea) }
    }

    private func selectedGapIndex(in blocks: [Block]) -> Int? {
        guard let sel = selected, let block = blockContaining(sel, in: blocks) else { return nil }
        return block.mirrored ? block.id - 1 : block.id
    }

    private func blockView(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.showsLabel ? lot.document.bays[block.bay].name.uppercased() : " ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 18)
                .padding(.bottom, 8)
            ForEach(block.range, id: \.self) { i in
                stall(bay: block.bay, idea: i, mirrored: block.mirrored)
            }
        }
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
                    .onTapGesture { toggle(ref) }
            }
            Text(parked.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk.opacity(out ? 0.6 : 1))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 28)
        }
        .frame(width: stallWidth, height: stallHeight)
        .overlay(stallLines(mirrored: mirrored))
    }

    /// Painted stall lines: top, bottom, and the closed end. The open end
    /// faces the gap the car noses into.
    private func stallLines(mirrored: Bool) -> some View {
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

    private func gapView(index: Int, open: Bool, blocks: [Block]) -> some View {
        Group {
            if open, let sel = selected, let parked = idea(sel),
               let block = blockContaining(sel, in: blocks) {
                VStack(alignment: .leading, spacing: 10) {
                    CarSprite(color: Palette.card(parked.color).color)
                        .frame(width: 190)
                        .scaleEffect(x: block.mirrored ? -1 : 1)
                        .matchedGeometryEffect(id: sel, in: carSpace)
                        .onTapGesture { close() }
                    IdeaPanel(lot: lot, bay: sel.bay, idea: sel.idea) { target in
                        moveSelected(toBay: target)
                    }
                    .id(sel)
                    .frame(width: 264)
                }
                .padding(.top, 26 + CGFloat(sel.idea - block.range.lowerBound) * stallHeight)
                .padding(.horizontal, 18)
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

/// The pulled-out idea. The panel is the markdown, not a form: the first line
/// is the title, the rest is the details. No save button; edits splice back
/// through the store's debounce. The caret lands on open.
private struct IdeaPanel: View {
    @ObservedObject var lot: ParkingLotStore
    let bay: Int
    let idea: Int
    var onMoveToBay: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(lot: ParkingLotStore, bay: Int, idea: Int, onMoveToBay: @escaping (String) -> Void) {
        self._lot = ObservedObject(wrappedValue: lot)
        self.bay = bay
        self.idea = idea
        self.onMoveToBay = onMoveToBay
        let parked = lot.document.bays[bay].ideas[idea]
        self._draft = State(initialValue: parked.details.isEmpty
            ? parked.title
            : parked.title + "\n" + parked.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaLine
            TextEditor(text: $draft)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .frame(minHeight: 90, maxHeight: 220)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.957, green: 0.945, blue: 0.91)))
        .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 5)
        .onAppear { focused = true }
        .onChange(of: draft) { _, text in
            let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let color = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].color : nil
            lot.update(
                bayIndex: bay, ideaIndex: idea,
                title: String(parts.first ?? "").trimmingCharacters(in: .whitespaces),
                details: parts.count > 1 ? String(parts[1]) : "",
                color: color)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let parked = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].parked : nil {
                Text("PARKED \(parked)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
