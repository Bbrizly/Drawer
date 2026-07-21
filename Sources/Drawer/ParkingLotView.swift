import AppKit
import DrawerCore
import SwiftUI

/// The lot: bays from the markdown as rows of painted stalls, one car per
/// stall in file order. Bays stack down the page the way they sit in the
/// file, and a bay's cars fill left to right and wrap at the window edge, so
/// the lot is only ever as wide as the window and you read it top to bottom.
/// Every row paints its full width of lines, so the lot looks like a lot even
/// where no car is parked; tapping an empty stall parks a fresh idea there.
/// Pressing a car reverses it out into the lane below and opens its markdown.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore
    @Binding var zoom: CGFloat
    var resetRequests: Int
    /// Set by the header's bay menu. The lot pans to that bay and clears it.
    @Binding var jumpToBay: Int?

    @State private var gestureZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    @State private var lotFrame: CGRect = .zero
    @State private var scrollMonitor: Any?
    @State private var selected: IdeaRef?
    @State private var renamingBay: Int?
    @State private var bayDraft = ""
    @State private var dropTargetBay: Int?
    /// The idea a tap on an empty space just created. Closing without typing
    /// hands the space back; nothing else is ever deleted by closing.
    @State private var blankIdea: IdeaRef?
    @State private var hovered: IdeaRef?
    @FocusState private var bayFieldFocused: Bool
    @Namespace private var carSpace

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int

        /// What a dragged car carries. A plain string keeps the drag on
        /// SwiftUI's own Transferable path with no custom UTType to register.
        var payload: String { "\(bay):\(idea)" }

        init(bay: Int, idea: Int) {
            self.bay = bay
            self.idea = idea
        }

        init?(payload: String) {
            let parts = payload.split(separator: ":")
            guard parts.count == 2, let b = Int(parts[0]), let i = Int(parts[1]) else { return nil }
            self.init(bay: b, idea: i)
        }
    }

    // A stall is taller than it is wide, the way a real space is: the car
    // noses in from the lane below and the stencil reads underneath it.
    private let stallWidth: CGFloat = 132
    private let stallHeight: CGFloat = 140
    /// The bay sign strip above each row block.
    private let signHeight: CGFloat = 36
    /// The lane between one bay and the next.
    private let laneHeight: CGFloat = 18
    private let edgePad: CGFloat = 22
    private var carLength: CGFloat { stallWidth - 54 }
    private var carWidth: CGFloat { carLength * 128 / 300 }
    private let panelWidth: CGFloat = 400

    private let asphalt = Color(red: 0.153, green: 0.153, blue: 0.168)
    private let paint = Color.white.opacity(0.14)
    private let curb = Color.white.opacity(0.26)
    private let stencilInk = Color.white.opacity(0.62)

    var body: some View {
        GeometryReader { geo in
            let perRow = perRow(for: geo.size.width)
            ZStack(alignment: .topLeading) {
                lotBody(perRow: perRow)
                    .padding(edgePad)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Zoom about the middle of the viewport, the way the idea board
            // does. Scaling from the corner and then shifting by half the
            // viewport times (1 - zoom) puts the centre point back where it
            // was, on both axes. Panning sits outside the scale, so a drag
            // moves the lot one screen point per pointer point at any zoom.
            .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
            .offset(
                x: offset.width + dragOffset.width
                    + geo.size.width / 2 * (1 - zoom * gestureZoom),
                y: offset.height + dragOffset.height
                    + geo.size.height / 2 * (1 - zoom * gestureZoom))
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
            .onChange(of: jumpToBay) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    offset = CGSize(
                        width: 0,
                        height: topOffset(forBay: target, perRow: perRow, viewport: geo.size))
                }
                jumpToBay = nil
            }
            .onAppear {
                lotFrame = geo.frame(in: .global)
                installScrollMonitor()
            }
            .onChange(of: geo.frame(in: .global)) { _, frame in
                lotFrame = frame
            }
            // An outside edit renumbers the bays and ideas under us. An open
            // card still points at the old position, so one more keystroke
            // would splice its text over whatever moved into that slot. Let go
            // instead. Nothing is lost: a reload only happens when no save is
            // pending, so everything typed so far is already on disk.
            .onChange(of: lot.reloads) { _, _ in
                selected = nil
                blankIdea = nil
                renamingBay = nil
            }
            .onDisappear { removeScrollMonitor() }
        }
    }

    // MARK: - Layout maths

    private func perRow(for width: CGFloat) -> Int {
        max(1, Int((width - edgePad * 2) / stallWidth))
    }

    private func bayHeight(_ ideas: Int, perRow: Int) -> CGFloat {
        let rows = ParkingLotLayout.rows(ideas: ideas, perRow: perRow)
        return signHeight + CGFloat(rows) * stallHeight + laneHeight
    }

    /// The pan offset that puts a bay's sign just under the top edge. Inverts
    /// the same transform the body applies: a point at content y lands on
    /// screen at y * zoom + offset + viewport/2 * (1 - zoom).
    private func topOffset(forBay bay: Int, perRow: Int, viewport: CGSize) -> CGFloat {
        var y = edgePad
        for (i, b) in lot.document.bays.enumerated() {
            if i == bay { break }
            y += bayHeight(b.ideas.count, perRow: perRow)
        }
        return edgePad - y * zoom - viewport.height / 2 * (1 - zoom)
    }

    // MARK: - Panning

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

    // MARK: - The lot

    @ViewBuilder
    private func lotBody(perRow: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if lot.document.bays.isEmpty {
                emptyLot(perRow: perRow)
            } else {
                ForEach(Array(lot.document.bays.enumerated()), id: \.offset) { b, bay in
                    bayBlock(bay: b, ideas: bay.ideas.count, perRow: perRow)
                }
            }
        }
        .animation(.easeOut(duration: 0.28), value: selected)
    }

    private func emptyLot(perRow: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            baySign(nil, width: CGFloat(perRow) * stallWidth)
            HStack(spacing: 0) {
                ForEach(0..<perRow, id: \.self) { _ in
                    EmptyStall(width: stallWidth, height: stallHeight, paint: paint, curb: curb) {
                        addIdea(toBay: "Unsorted")
                    }
                }
            }
        }
    }

    /// One bay: its sign, then its cars flowing left to right and wrapping,
    /// then the open panel if the selected car lives in this bay.
    private func bayBlock(bay b: Int, ideas: Int, perRow: Int) -> some View {
        let rows = ParkingLotLayout.rows(ideas: ideas, perRow: perRow)
        let width = CGFloat(perRow) * stallWidth
        let bayName = lot.document.bays[b].name
        return VStack(alignment: .leading, spacing: 0) {
            baySign(b, width: width)
            ForEach(0..<rows, id: \.self) { row in
                let start = row * perRow
                let end = min(start + perRow, ideas)
                HStack(spacing: 0) {
                    if start < end {
                        ForEach(start..<end, id: \.self) { i in
                            stall(bay: b, idea: i)
                        }
                    }
                    // The painted lines exist before the cars do: pad the row
                    // out with empty spaces, each one a tap target.
                    ForEach(0..<(perRow - max(0, end - start)), id: \.self) { _ in
                        EmptyStall(
                            width: stallWidth, height: stallHeight,
                            paint: paint, curb: curb
                        ) {
                            addIdea(toBay: bayName)
                        }
                    }
                }
                if let sel = selected, sel.bay == b,
                   sel.idea >= start, sel.idea < end {
                    openPanel(sel, column: sel.idea - start, width: width)
                }
            }
            Color.clear.frame(height: laneHeight)
        }
        .frame(width: width, alignment: .leading)
        // Drop a dragged car anywhere on the bay to re-park it here.
        .background(dropTargetBay == b ? Color.white.opacity(0.05) : .clear)
        .dropDestination(for: String.self) { items, _ in
            guard let ref = IdeaRef(payload: items.first ?? "") else { return false }
            drop(ref, toBay: bayName)
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTargetBay = b
            } else if dropTargetBay == b {
                // Only clear our own highlight; the next bay may have already
                // claimed it as the pointer crossed over.
                dropTargetBay = nil
            }
        }
    }

    /// The car out in the lane with its markdown under it. Sits at the column
    /// the car came from, nudged left only as far as it must to stay on the
    /// lot, so the drive out reads as a straight line down.
    private func openPanel(_ sel: IdeaRef, column: Int, width: CGFloat) -> some View {
        let carX = CGFloat(column) * stallWidth
        let panelX = min(carX, max(0, width - panelWidth))
        return VStack(alignment: .leading, spacing: 10) {
            if let parked = idea(sel) {
                CarSprite(color: Palette.card(parked.color).color)
                    .frame(width: carLength, height: carWidth)
                    .rotationEffect(.degrees(-90))
                    .frame(width: carWidth, height: carLength)
                    .matchedGeometryEffect(id: sel, in: carSpace)
                    .padding(.leading, carX + (stallWidth - carWidth) / 2)
                    .onTapGesture { close() }
                IdeaPanel(
                    lot: lot, bay: sel.bay, idea: sel.idea,
                    onMoveToBay: { target in moveSelected(toBay: target) },
                    onClose: { close() })
                    .id(sel)
                    .frame(width: min(panelWidth, width))
                    .padding(.leading, panelX)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Bay signs

    /// Bay headings may read `2026-07-18: B2B money track (some aside)`. The
    /// sign wants the category, so the date comes off the front and rides as a
    /// small stamp, and a trailing aside comes off the back. The full heading
    /// stays in the tooltip, and renaming only ever touches the category.
    static func baySign(_ name: String) -> (date: String?, category: String) {
        var rest = name
        var date: String?
        // A heading that is nothing but a date has no category to show, so the
        // date still comes off the front rather than becoming the sign.
        if let m = rest.firstMatch(of: #/^(\d{4}-\d{2}-\d{2})(\s*:\s*|\s*$)/#) {
            date = String(m.1)
            rest = String(rest[m.range.upperBound...])
        }
        return (date, rest.trimmingCharacters(in: .whitespaces))
    }

    /// Drops a trailing "(...)" so long headings read as categories on the
    /// sign. Never returns empty: a name that is only an aside keeps it.
    static func signCategory(_ category: String) -> String {
        guard category.hasSuffix(")"), let open = category.lastIndex(of: "(") else {
            return category
        }
        let short = category[..<open].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? category : short
    }

    /// The sign over a bay: name on the left, count on the right, a painted
    /// rule under both. Double-click the name to rename the bay, which
    /// rewrites the `## ` heading in the file.
    @ViewBuilder
    private func baySign(_ bayIndex: Int?, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let b = bayIndex, lot.document.bays.indices.contains(b) {
                    let bay = lot.document.bays[b]
                    let sign = Self.baySign(bay.name)

                    if renamingBay == b {
                        TextField("Name", text: $bayDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .focused($bayFieldFocused)
                            .onSubmit { commitRename() }
                            .onChange(of: bayFieldFocused) { _, focused in
                                if !focused { commitRename() }
                            }
                    } else {
                        Text(Self.signCategory(sign.category).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("\(bay.name)\n\nDouble-click to rename")
                            .onTapGesture(count: 2) { beginRename(b) }
                    }
                    if let date = sign.date {
                        Text(date)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer(minLength: 8)
                    // Tabular so the count never jiggles the rule as it changes.
                    Text("\(bay.ideas.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                    SignParkButton { addIdea(toBay: bay.name) }
                } else {
                    Text("UNSORTED")
                        .font(.system(size: 13, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer(minLength: 8)
                }
            }
            .frame(height: signHeight - 8, alignment: .bottom)
            Rectangle()
                .fill(curb)
                .frame(height: 1.5)
        }
        .frame(width: width, height: signHeight, alignment: .bottomLeading)
    }

    /// Renaming edits the category only. The date prefix is the file's, not
    /// the sign's, so it goes back on untouched.
    private func beginRename(_ bay: Int) {
        // The tap can land after an outside edit dropped this bay.
        guard lot.document.bays.indices.contains(bay) else { return }
        bayDraft = Self.baySign(lot.document.bays[bay].name).category
        renamingBay = bay
        bayFieldFocused = true
    }

    private func commitRename() {
        guard let b = renamingBay, lot.document.bays.indices.contains(b) else { return }
        renamingBay = nil
        bayFieldFocused = false
        let typed = bayDraft.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        if let date = Self.baySign(lot.document.bays[b].name).date {
            lot.renameBay(index: b, to: "\(date): \(typed)")
        } else {
            lot.renameBay(index: b, to: typed)
        }
    }

    // MARK: - Stalls

    private func stall(bay: Int, idea: Int) -> some View {
        let ref = IdeaRef(bay: bay, idea: idea)
        let parked = lot.document.bays[bay].ideas[idea]
        let out = selected == ref
        let lit = hovered == ref
        return VStack(spacing: 9) {
            Group {
                if out {
                    // The car is out in the lane; keep its footprint.
                    Color.clear
                } else {
                    CarSprite(color: Palette.card(parked.color).color)
                        .frame(width: carLength, height: carWidth)
                        .rotationEffect(.degrees(-90))
                        .matchedGeometryEffect(id: ref, in: carSpace)
                        .draggable(ref.payload) {
                            CarSprite(color: Palette.card(parked.color).color)
                                .frame(width: carLength, height: carWidth)
                        }
                }
            }
            // Fixed footprint, so every car sits at the same y in its stall
            // and the drive out is dead straight.
            .frame(width: carWidth, height: carLength)
            Text(parked.title.isEmpty ? "UNTITLED" : parked.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk.opacity(out ? 0.5 : 1))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 14, height: 28, alignment: .top)
        }
        .padding(.top, 14)
        .frame(width: stallWidth, height: stallHeight, alignment: .top)
        // Hover lifts the whole space, not just the car, so the stencil reads
        // as part of the same target.
        .background(Color.white.opacity(lit && !out ? 0.05 : 0))
        .scaleEffect(lit && !out ? 1.03 : 1)
        .animation(.easeOut(duration: 0.14), value: lit)
        // The whole stall is the target, stencil included, not just the car.
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? ref : (hovered == ref ? nil : hovered) }
        .onTapGesture { toggle(ref) }
        .overlay(StallLines(paint: paint, curb: curb))
        .help(parked.title.isEmpty ? "Untitled idea" : parked.title)
    }

    // MARK: - Actions

    /// Re-parks a dragged car. Moving inside its own bay is a no-op: a lot has
    /// no order worth preserving, so there is nothing to reorder into.
    // ponytail: bay-level moves only, add within-bay ordering if a lot ever gets one.
    private func drop(_ ref: IdeaRef, toBay name: String) {
        dropTargetBay = nil
        guard let dragged = idea(ref),
              lot.document.bays[ref.bay].name != name else { return }
        // Closing can delete a blank idea, which renumbers the rest of its bay
        // and leaves the dragged car's index pointing at its neighbour. Find
        // the car again by what it holds instead of trusting the old index.
        if selected != nil { close() }
        guard let now = locate(dragged) else { return }
        lot.move(bayIndex: now.bay, ideaIndex: now.idea, toBay: name)
    }

    /// Where an idea sits now. Matched on content, not on `lineRange`, because
    /// a delete anywhere above it rewrites every line number below.
    private func locate(_ target: ParkedIdea) -> IdeaRef? {
        for (b, bay) in lot.document.bays.enumerated() {
            if let i = bay.ideas.firstIndex(where: {
                $0.title == target.title && $0.details == target.details
                    && $0.parked == target.parked && $0.color == target.color
            }) {
                return IdeaRef(bay: b, idea: i)
            }
        }
        return nil
    }

    private func addIdea(toBay name: String) {
        if selected != nil { close() }
        lot.park(title: "", details: "", toBay: name)
        guard let b = lot.document.bays.firstIndex(where: { $0.name == name }),
              !lot.document.bays[b].ideas.isEmpty else { return }
        selected = IdeaRef(bay: b, idea: lot.document.bays[b].ideas.count - 1)
        // Only this one may vanish on close. An idea that already had a title
        // is safe even if you clear the field to retype it.
        blankIdea = selected
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

    /// Reverses the car back in. A space you parked in and then typed nothing
    /// into is given back, no confirmation. An idea that already had a title
    /// stays even if you clear the field, since there is no undo to lean on.
    private func close() {
        guard let sel = selected else { return }
        if sel == blankIdea, let parked = idea(sel),
           parked.title.isEmpty, parked.details.isEmpty {
            lot.delete(bayIndex: sel.bay, ideaIndex: sel.idea)
        }
        blankIdea = nil
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

/// Painted stall lines: the dividers down each side and the curb across the
/// head of the space. The foot stays open, facing the lane the car noses out
/// into.
private struct StallLines: View {
    let paint: Color
    let curb: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.move(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(paint, lineWidth: 2)
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(curb, lineWidth: 2)
            }
        }
    }
}

/// The + on a bay sign. Always in the same place, so parking into a bay never
/// depends on there happening to be a painted empty space in view.
private struct SignParkButton: View {
    var onPark: () -> Void

    @State private var hovered = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(hovered ? 0.9 : 0.4))
            // The glyph is 11pt; the frame is what your pointer actually has
            // to hit.
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.white.opacity(hovered ? 0.12 : 0)))
            .contentShape(Circle())
            .onHover { hovered = $0 }
            .onTapGesture { onPark() }
            .animation(.easeOut(duration: 0.14), value: hovered)
            .help("Park a new idea in this bay")
    }
}

/// A painted space with no car in it. Hover shows a faint plus; a tap parks a
/// fresh idea there, and closing the panel without typing removes it again.
private struct EmptyStall: View {
    let width: CGFloat
    let height: CGFloat
    let paint: Color
    let curb: Color
    var onPark: () -> Void

    @State private var hovered = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(hovered ? 0.4 : 0))
            .frame(width: width, height: height)
            .background(Color.white.opacity(hovered ? 0.04 : 0))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { onPark() }
            .overlay(StallLines(paint: paint, curb: curb))
            .animation(.easeOut(duration: 0.14), value: hovered)
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

    @State private var title: String
    @State private var details: String
    @FocusState private var focusedField: Field?

    private enum Field { case title, details }

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
        self._title = State(initialValue: parked.title)
        self._details = State(initialValue: parked.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metaLine

            // The title is its own field, big, because it is the one line the
            // stall stencil shows. It is still just the first line of the
            // markdown bullet underneath.
            TextField("Idea", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .semibold))
                .focused($focusedField, equals: .title)
                .onSubmit { focusedField = .details }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)

            // Grows with what you type instead of opening as a tall empty box.
            TextEditor(text: $details)
                .focused($focusedField, equals: .details)
                .scrollContentBackground(.hidden)
                .font(.system(size: 15))
                .lineSpacing(3)
                .frame(minHeight: 64, maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Details")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 5)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                // The text view eats Escape for completions, so onExitCommand
                // never fires while typing. Catch the key itself.
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }

            colorRow
        }
        .padding(14)
        // Concentric: the 14pt inset inside a 26pt corner leaves the inner
        // content sitting on a 12pt curve, so nothing reads pinched.
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(red: 0.957, green: 0.945, blue: 0.91)))
        .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
        // Layered rather than one hard shadow, so the panel lifts off the
        // asphalt instead of sitting on a drawn edge.
        .shadow(color: .black.opacity(0.30), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
        .shadow(color: .black.opacity(0.14), radius: 24, y: 14)
        .onAppear { focusedField = .title }
        .onChange(of: title) { _, _ in save() }
        .onChange(of: details) { _, _ in save() }
    }

    private func save() {
        lot.update(
            bayIndex: bay, ideaIndex: idea,
            title: title.trimmingCharacters(in: .whitespaces),
            details: details, color: currentColor)
    }

    private var currentColor: String? {
        guard lot.document.bays.indices.contains(bay),
              lot.document.bays[bay].ideas.indices.contains(idea) else { return nil }
        return lot.document.bays[bay].ideas[idea].color
    }

    private var colorRow: some View {
        HStack(spacing: 2) {
            ForEach(Self.colorKeys, id: \.self) { key in
                let active = key == (currentColor ?? "yellow")
                Circle()
                    .fill(Palette.card(key).color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(
                        Color.black.opacity(active ? 0.55 : 0.12),
                        lineWidth: active ? 2 : 1))
                    .scaleEffect(active ? 1.18 : 1)
                    .animation(.easeOut(duration: 0.15), value: active)
                    // A 16pt dot is a 16pt target unless you say otherwise.
                    // The frame gives it a real one without growing the dot.
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                    .onTapGesture {
                        lot.update(
                            bayIndex: bay, ideaIndex: idea,
                            title: title.trimmingCharacters(in: .whitespaces),
                            details: details, color: key)
                    }
                    .help(key.capitalized)
            }
            Spacer()
        }
        .padding(.leading, -7)
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let parked = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].parked : nil {
                Text("PARKED \(parked)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
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
