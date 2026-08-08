import DrawerCore
import SwiftUI

/// The lot: every idea in the file as a card, bays as headings that stick to
/// the top while you scroll past them, so you always know which category you
/// are reading. It scrolls, it does not pan. Only the bays on screen are ever
/// built, and a card is a filled rectangle with wrapped text on it, so the
/// whole board costs about what a list costs.
///
/// It used to be a drawn car park: painted stalls, a car sprite per idea, pan
/// and zoom over a canvas bigger than the window. It looked good and it was
/// slow, and two ideas per row meant you could never see the lot you were
/// meant to be surveying. The metaphor stays in the name, the file, and the
/// little car you drag between bays.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore
    /// Card size. Zoom out to survey everything, zoom in to read it.
    @Binding var zoom: CGFloat
    /// Bumped by the header's reset button: back to the top at normal size.
    var resetRequests: Int
    /// Set by the header's bay menu. The lot scrolls to that bay and clears it.
    @Binding var jumpToBay: Int?

    @State private var selected: IdeaRef?
    @State private var renamingBay: Int?
    @State private var bayDraft = ""
    @State private var deletingBay: Int?
    @State private var addingBay = false
    @State private var newBayDraft = ""
    /// The idea a tap on the + just created. Closing without typing hands the
    /// space back; nothing else is ever deleted by closing.
    @State private var blankIdea: IdeaRef?
    @FocusState private var bayFieldFocused: Bool
    @FocusState private var newBayFocused: Bool

    /// Which bays are rolled up. Names, not indexes, so reordering the lot or
    /// editing the file by hand does not shuffle what is collapsed. Lives in
    /// defaults because it is a view preference, not the user's file.
    @AppStorage("lotCollapsedBays") private var collapsedRaw = ""

    /// What the board page gave us. The width picks the column count, the
    /// height caps the open card. Read by `onGeometryChange`, never measured
    /// mid-layout.
    @State private var lotSize: CGSize = .zero

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int

        /// What a dragged card carries. A plain string keeps the drag on
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

    /// Card size at zoom 1. Wide enough that a full sentence of a title reads
    /// as a sentence, which is most of what a card is for.
    private let baseCardWidth: CGFloat = 196
    private let baseCardHeight: CGFloat = 88
    private let gutter: CGFloat = 8
    private let edgePad: CGFloat = 14
    private let signHeight: CGFloat = 34

    private let asphalt = Color(red: 0.153, green: 0.153, blue: 0.168)
    private let curb = Color.white.opacity(0.22)

    private var cardWidth: CGFloat { baseCardWidth * zoom }
    private var cardHeight: CGFloat { baseCardHeight * zoom }

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "\n").map(String.init))
    }

    /// Measured against the bays that exist, not the count: a name left in
    /// defaults by a bay you deleted must not read as one that is rolled up.
    private var allCollapsed: Bool {
        let shut = collapsed
        return !lot.document.bays.isEmpty && lot.document.bays.allSatisfy {
            shut.contains($0.name)
        }
    }

    var body: some View {
            VStack(spacing: 0) {
                lotBar
                ScrollViewReader { proxy in
                    ScrollView {
                        // Plain, not lazy, and this is the whole reason the lot
                        // stopped freezing. A lazy stack works out which bays
                        // are on screen from a height it is working out from
                        // which bays are on screen. On a long lot that argument
                        // never ends: the main thread spins at 100% and the app
                        // has to be killed. Every sample of the freeze was
                        // inside that placement. A plain stack has no such
                        // question to answer. It builds every bay, which a file
                        // of categories can afford, and collapsing a bay still
                        // takes its cards out of the layout entirely.
                        VStack(alignment: .leading, spacing: 0) {
                            if lot.document.bays.isEmpty {
                                emptyLot
                            } else {
                                ForEach(Array(lot.document.bays.enumerated()), id: \.offset) { b, bay in
                                    baySign(b)
                                        .id(b)
                                    if !collapsed.contains(bay.name) {
                                        BayGrid(
                                            bay: b,
                                            bayColor: Palette.card(bay.color).color,
                                            ideas: bay.ideas,
                                            columns: columns(in: lotSize.width),
                                            cardHeight: cardHeight,
                                            gutter: gutter,
                                            zoom: zoom,
                                            onTap: { toggle($0) },
                                            onDelete: { delete($0) },
                                            onDrop: { ref in drop(ref, toBay: bay.name) }
                                        )
                                        .padding(.horizontal, edgePad)
                                        .padding(.bottom, 18)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .onChange(of: resetRequests) { _, _ in
                        zoom = 1
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(0, anchor: .top) }
                    }
                    .onChange(of: jumpToBay) { _, target in
                        guard let target else { return }
                        setCollapsed(target, false)
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                        jumpToBay = nil
                    }
                }
            }
            // The panel's own size, read once and parked in state. A
            // GeometryReader wrapped around this instead sat in the layout
            // itself and asked the scroll view how big it was every pass,
            // which is the other half of the loop above. This reports a
            // settled number and only wakes the view when it actually changes.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { lotSize = $0 }
            .background(asphalt)
            // An outside edit renumbers the bays and ideas under us. An open card
            // still points at the old position, so one more keystroke would splice
            // its text over whatever moved into that slot. Let go instead. Nothing
            // is lost: a reload only happens when no save is pending, so everything
            // typed so far is already on disk.
            .onChange(of: lot.reloads) { _, _ in
                selected = nil
                blankIdea = nil
                renamingBay = nil
            }
            .overlay { editor(in: lotSize.height) }
            .confirmationDialog(
                deletingBay.map { bayName($0) }.map { "Delete \($0)?" } ?? "Delete this category?",
                isPresented: Binding(
                    get: { deletingBay != nil },
                    set: { if !$0 { deletingBay = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete category and its ideas", role: .destructive) {
                    if let b = deletingBay { lot.deleteBay(index: b) }
                    deletingBay = nil
                }
                Button("Cancel", role: .cancel) { deletingBay = nil }
            } message: {
                Text("Every idea parked here goes with it. This edits your file and there is no undo.")
            }
    }

    /// How many cards fit across. The lot lays its own rows out rather than
    /// handing the job to an adaptive grid, so this is the one number the
    /// layout needs and it comes from the panel, not from the cards. N cards
    /// take N widths and N-1 gutters between them.
    static func columns(
        width: CGFloat, cardWidth: CGFloat, gutter: CGFloat, edgePad: CGFloat
    ) -> Int {
        let usable = width - edgePad * 2
        guard usable > 0, cardWidth > 0 else { return 1 }
        return max(1, Int((usable + gutter) / (cardWidth + gutter)))
    }

    /// Card slots chunked into rows. Indexes, not ideas, because a card needs
    /// its slot in the bay to address itself back to the store.
    static func rows(count: Int, columns: Int) -> [[Int]] {
        let per = max(1, columns)
        return stride(from: 0, to: max(0, count), by: per).map {
            Array($0..<min($0 + per, count))
        }
    }

    private func columns(in width: CGFloat) -> Int {
        Self.columns(
            width: width, cardWidth: cardWidth, gutter: gutter, edgePad: edgePad)
    }

    // MARK: - The bar over the lot

    /// Collapse and expand live here rather than in a per-bay menu only,
    /// because surveying forty bays starts by rolling them all up.
    private var lotBar: some View {
        HStack(spacing: 6) {
            Button {
                setAllCollapsed(!allCollapsed)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: allCollapsed
                          ? "chevron.down.square" : "chevron.up.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(allCollapsed ? "Expand all" : "Collapse all")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.62))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(allCollapsed ? "Open every category" : "Roll every category up")

            Spacer(minLength: 8)

            if addingBay {
                TextField("Category", text: $newBayDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 150)
                    .focused($newBayFocused)
                    .onSubmit { commitNewBay() }
                    .onChange(of: newBayFocused) { _, focused in
                        if !focused { commitNewBay() }
                    }
            } else {
                Button {
                    newBayDraft = ""
                    addingBay = true
                    newBayFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Category")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a category to the end of the lot")
            }
        }
        .padding(.horizontal, edgePad)
        .padding(.vertical, 7)
        .background(asphalt)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - The open idea

    /// The idea you clicked, over a scrim. It used to reverse out into a lane
    /// below its stall, which meant the board reflowed around it every time.
    /// Floating it costs the board nothing.
    @ViewBuilder
    private func editor(in height: CGFloat) -> some View {
        if let sel = selected, idea(sel) != nil {
            ZStack {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                IdeaPanel(
                    lot: lot, bay: sel.bay, idea: sel.idea,
                    // Whatever the board page gave us, less the padding. The
                    // panel spends it on the note so an idea reads as a block
                    // instead of through a letterbox.
                    available: max(220, height - 40),
                    onDelete: { deleteSelected() },
                    onClose: { close() })
                    .id(sel)
                    .frame(maxWidth: 520)
                    .padding(20)
            }
            .transition(.opacity)
        }
    }

    private var emptyLot: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing parked yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Button("Park an idea") { addIdea(toBay: "Unsorted") }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(edgePad)
        .padding(.top, 30)
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

    /// The sign over a bay: a collapse chevron, the name, the count, a plus,
    /// and the menu that owns the category itself. Double-click the name to
    /// rename, which rewrites the `## ` heading in the file. It is opaque
    /// because it sticks to the top of the scroll and cards pass underneath.
    @ViewBuilder
    private func baySign(_ b: Int) -> some View {
        if lot.document.bays.indices.contains(b) {
            let bay = lot.document.bays[b]
            let isCollapsed = collapsed.contains(bay.name)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Button {
                        setCollapsed(b, !isCollapsed)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .black))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 16, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Open this category" : "Roll this category up")

                    if let color = bay.color {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Palette.card(color).color)
                            .frame(width: 4, height: 13)
                    }

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
                        Text(Self.signCategory(Self.baySign(bay.name).category).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help("\(bay.name)\n\nDouble-click to rename")
                            .onTapGesture(count: 2) { beginRename(b) }
                    }
                    Spacer(minLength: 8)
                    // Tabular so the count never jiggles the rule as it changes.
                    Text("\(bay.ideas.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                    SignParkButton { addIdea(toBay: bay.name) }
                    bayMenu(b, bay: bay, isCollapsed: isCollapsed)
                }
                .padding(.horizontal, edgePad)
                .frame(height: signHeight - 6, alignment: .bottom)
                Rectangle()
                    .fill(curb)
                    .frame(height: 1.5)
            }
            .padding(.top, 8)
            .background(asphalt)
        }
    }

    /// Everything you can do to a category. One menu keeps the sign clean at
    /// any zoom, and it is where colour lives now that cards do not carry
    /// their own swatch.
    private func bayMenu(_ b: Int, bay: ParkingBay, isCollapsed: Bool) -> some View {
        Menu {
            Button("Rename") { beginRename(b) }
            Button(isCollapsed ? "Expand" : "Collapse") { setCollapsed(b, !isCollapsed) }
            Menu("Colour") {
                ForEach(IdeaPanel.colorKeys, id: \.self) { key in
                    Button(key.capitalized) { lot.setBayColor(index: b, to: key) }
                }
                Divider()
                Button("None") { lot.setBayColor(index: b, to: nil) }
            }
            Divider()
            Button("Move to top") { lot.moveBay(from: b, to: 0) }
                .disabled(b == 0)
            Button("Move up") { lot.moveBay(from: b, to: b - 1) }
                .disabled(b == 0)
            Button("Move down") { lot.moveBay(from: b, to: b + 1) }
                .disabled(b >= lot.document.bays.count - 1)
            Button("Move to bottom") { lot.moveBay(from: b, to: lot.document.bays.count - 1) }
                .disabled(b >= lot.document.bays.count - 1)
            Divider()
            Button("Delete category", role: .destructive) { deletingBay = b }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .help("Category options")
        .accessibilityLabel("Category options")
    }

    private func bayName(_ b: Int) -> String {
        guard lot.document.bays.indices.contains(b) else { return "this category" }
        return Self.signCategory(Self.baySign(lot.document.bays[b].name).category)
    }

    // MARK: - Collapse

    private func setCollapsed(_ b: Int, _ shut: Bool) {
        guard lot.document.bays.indices.contains(b) else { return }
        var names = collapsed
        if shut { names.insert(lot.document.bays[b].name) }
        else { names.remove(lot.document.bays[b].name) }
        collapsedRaw = names.sorted().joined(separator: "\n")
    }

    private func setAllCollapsed(_ shut: Bool) {
        collapsedRaw = shut
            ? lot.document.bays.map(\.name).sorted().joined(separator: "\n")
            : ""
    }

    // MARK: - Actions

    /// Re-parks a dragged card. Moving inside its own bay is a no-op: a lot has
    /// no order worth preserving, so there is nothing to reorder into.
    // ponytail: bay-level moves only, add within-bay ordering if a lot ever gets one.
    private func drop(_ ref: IdeaRef, toBay name: String) {
        guard let dragged = idea(ref),
              lot.document.bays[ref.bay].name != name else { return }
        // Closing can delete a blank idea, which renumbers the rest of its bay
        // and leaves the dragged card's index pointing at its neighbour. Find
        // the idea again by what it holds instead of trusting the old index.
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
        setCollapsedByName(name, false)
        lot.park(title: "", details: "", toBay: name)
        guard let b = lot.document.bays.firstIndex(where: { $0.name == name }),
              !lot.document.bays[b].ideas.isEmpty else { return }
        selected = IdeaRef(bay: b, idea: lot.document.bays[b].ideas.count - 1)
        // Only this one may vanish on close. An idea that already had a title
        // is safe even if you clear the field to retype it.
        blankIdea = selected
    }

    private func setCollapsedByName(_ name: String, _ shut: Bool) {
        var names = collapsed
        if shut { names.insert(name) } else { names.remove(name) }
        collapsedRaw = names.sorted().joined(separator: "\n")
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

    /// Closes the open idea. A card you made and then typed nothing into is
    /// given back, no confirmation. An idea that already had a title stays even
    /// if you clear the field, since there is no undo to lean on.
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

    private func delete(_ ref: IdeaRef) {
        guard idea(ref) != nil else { return }
        if selected == ref { selected = nil; blankIdea = nil }
        lot.delete(bayIndex: ref.bay, ideaIndex: ref.idea)
    }

    private func deleteSelected() {
        guard let sel = selected else { return }
        selected = nil
        blankIdea = nil
        lot.delete(bayIndex: sel.bay, ideaIndex: sel.idea)
        lot.saveNow()
    }

    private func beginRename(_ bay: Int) {
        // The tap can land after an outside edit dropped this bay.
        guard lot.document.bays.indices.contains(bay) else { return }
        bayDraft = Self.baySign(lot.document.bays[bay].name).category
        renamingBay = bay
        bayFieldFocused = true
    }

    /// Renaming edits the category only. The date prefix is the file's, not
    /// the sign's, so it goes back on untouched.
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

    private func commitNewBay() {
        addingBay = false
        newBayFocused = false
        lot.addBay(named: newBayDraft)
        newBayDraft = ""
    }
}

/// One bay's cards, wrapping to fill the width.
///
/// Its own view for two reasons. The drop highlight lives in here, so dragging
/// a card across the board redraws one bay instead of the board. And the rows
/// are chunked by hand from a column count the lot worked out from the panel
/// width, so a bay's height is a plain sum of its rows. An adaptive grid would
/// work the count out for itself, from the space the enclosing scroll view has
/// left, which is the thing this height is supposed to be telling it.
private struct BayGrid: View {
    let bay: Int
    let bayColor: Color
    let ideas: [ParkedIdea]
    let columns: Int
    let cardHeight: CGFloat
    let gutter: CGFloat
    let zoom: CGFloat
    let onTap: (ParkingLotView.IdeaRef) -> Void
    let onDelete: (ParkingLotView.IdeaRef) -> Void
    let onDrop: (ParkingLotView.IdeaRef) -> Void

    @State private var targeted = false

    private var rows: [[Int]] {
        ParkingLotView.rows(count: ideas.count, columns: columns)
    }

    var body: some View {
        Group {
            if ideas.isEmpty {
                Text("Nothing parked here. Drop a card, or use the plus.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: gutter) {
                    // Keyed on the first card's line in the file, not on the row
                    // number: a delete above it must not hand this row's identity
                    // to its neighbour and make SwiftUI rebuild the tail.
                    ForEach(rows, id: \.first) { row in
                        HStack(alignment: .top, spacing: gutter) {
                            ForEach(row, id: \.self) { i in
                                IdeaCard(
                                    ref: ParkingLotView.IdeaRef(bay: bay, idea: i),
                                    title: ideas[i].title,
                                    details: ideas[i].details,
                                    color: ideas[i].color.map { Palette.card($0).color }
                                        ?? bayColor,
                                    minHeight: cardHeight,
                                    zoom: zoom,
                                    onTap: onTap,
                                    onDelete: onDelete
                                )
                            }
                            // Holds the empty slots open so a last row of one
                            // card is card-sized, not a banner across the lot.
                            if row.count < columns {
                                ForEach(row.count..<columns, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(targeted ? 0.07 : 0))
                .padding(-6)
        )
        .dropDestination(for: String.self) { items, _ in
            targeted = false
            guard let ref = ParkingLotView.IdeaRef(payload: items.first ?? "") else { return false }
            onDrop(ref)
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// One idea. A filled rectangle and its title, wrapped: the card grows to fit
/// the words rather than shrinking the words to fit the card, because a lot
/// you cannot read is not worth surveying. Nothing is drawn and nothing is
/// measured, so a hundred of these cost less than a dozen of the old
/// canvas-drawn cars.
private struct IdeaCard: View {
    let ref: ParkingLotView.IdeaRef
    let title: String
    let details: String
    let color: Color
    let minHeight: CGFloat
    let zoom: CGFloat
    let onTap: (ParkingLotView.IdeaRef) -> Void
    let onDelete: (ParkingLotView.IdeaRef) -> Void

    @State private var hovered = false

    var body: some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(.system(size: 13.5 * zoom, weight: .semibold))
            .lineLimit(10)
            .multilineTextAlignment(.leading)
            .foregroundStyle(Palette.cardInk.color)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(10 * zoom)
            // A floor first, then match the tallest card in the row. The row is
            // a plain HStack, so it settles this from its own children. Asking
            // for full height straight inside a lazy container instead means
            // asking for a number that container has not worked out yet, and
            // the two never agree: that is what wedged the app mid-scroll.
            .frame(minHeight: minHeight, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            // A dog-ear when there is more to read than the title.
            .overlay(alignment: .bottomTrailing) {
                if !details.isEmpty {
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 4, height: 4)
                        .padding(5)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(hovered ? 0.45 : 0.12), lineWidth: 1)
            )
            // No scale and no animation on hover. Scrolling drags every card
            // under the pointer in turn, and a per-card animation on each of
            // those crossings is a storm the panel does not need.
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { onTap(ref) }
            .contextMenu {
                Button("Delete idea", role: .destructive) { onDelete(ref) }
            }
            // The car survives as the thing you drag. It was the best part of
            // the old lot and it costs one sprite, once, mid-drag.
            .draggable(ref.payload) {
                CarSprite(color: color).frame(width: 78, height: 34)
            }
            // Only when there is something the card is not already showing.
            .help(details.isEmpty ? "" : details)
    }
}

/// The + on a bay sign. Always in the same place, so parking into a bay never
/// depends on there happening to be a free space in view.
private struct SignParkButton: View {
    var onPark: () -> Void

    @State private var hovered = false

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(hovered ? 0.9 : 0.45))
            // The glyph is 11pt; the frame is what your pointer actually has
            // to hit.
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white.opacity(hovered ? 0.12 : 0)))
            .contentShape(Circle())
            .onHover { hovered = $0 }
            .onTapGesture { onPark() }
            .help("Park a new idea in this bay")
    }
}

/// The pulled-out idea. The panel is the markdown, not a form: the first line
/// is the title, the rest is the details. No save button; edits splice back
/// through the store's debounce. The caret lands on open.
private struct IdeaPanel: View {
    @ObservedObject var lot: ParkingLotStore
    let bay: Int
    let idea: Int
    /// Height the lot can spare. The note grows into it instead of scrolling
    /// inside a short box, which is the whole point of opening a card.
    let available: CGFloat
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var title: String
    @State private var details: String
    @State private var confirmingDelete = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, details }

    /// The colour vocabulary, in a fixed order. Cards no longer carry their
    /// own swatch; the bay menu paints the whole category from this list.
    static let colorKeys = ["yellow", "pink", "blue", "green", "purple", "gray"]

    init(
        lot: ParkingLotStore, bay: Int, idea: Int, available: CGFloat,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._lot = ObservedObject(wrappedValue: lot)
        self.bay = bay
        self.idea = idea
        self.available = available
        self.onDelete = onDelete
        self.onClose = onClose
        let parked = lot.document.bays[bay].ideas[idea]
        self._title = State(initialValue: parked.title)
        self._details = State(initialValue: parked.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The title is its own field, big, because it is the one thing the
            // card shows. It is still just the first line of the markdown
            // bullet underneath. It wraps: a long idea is still one idea.
            TextField("Idea", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold))
                .lineLimit(1...6)
                .focused($focusedField, equals: .title)
                .onSubmit { focusedField = .details }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)

            // Takes every point the panel has left. A TextEditor is a scroll
            // view: it does not report how tall its text is, so asking it for
            // its ideal height (fixedSize) pinned it short and the note
            // scrolled no matter how high the ceiling was set. Give it the
            // room instead and the text just sits there.
            TextEditor(text: $details)
                .focused($focusedField, equals: .details)
                .scrollContentBackground(.hidden)
                .font(.system(size: 15))
                .lineSpacing(3)
                .frame(minHeight: 200, maxHeight: .infinity)
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

            footer
        }
        .padding(14)
        // Fills the board rather than sitting in the middle of it. An idea you
        // opened to read should be a block of text, not a letterbox.
        .frame(maxHeight: available)
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

    /// Delete on one side, done on the other. The parked date and the bay
    /// chip used to live up here; neither told you anything the lot does not,
    /// and the date is still in the file.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.62, green: 0.16, blue: 0.12))
            .confirmationDialog(
                "Delete this idea?", isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It comes out of your file. There is no undo.")
            }
            Spacer()
            Button("Done") { onClose() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
