import DrawerCore
import SwiftUI

/// The lot: every idea in the file as a card, bays as headings that stick to
/// the top while you scroll past them, so you always know which category you
/// are reading. It scrolls, it does not pan. Only the bays on screen are ever
/// built, and a card is a filled rectangle with a line of text on it, so the
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
    /// The idea a tap on the + just created. Closing without typing hands the
    /// space back; nothing else is ever deleted by closing.
    @State private var blankIdea: IdeaRef?
    @FocusState private var bayFieldFocused: Bool

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

    /// Card size at zoom 1. Narrow enough that a 400pt panel holds three.
    private let baseCardWidth: CGFloat = 112
    private let baseCardHeight: CGFloat = 62
    private let gutter: CGFloat = 7
    private let edgePad: CGFloat = 14
    private let signHeight: CGFloat = 34

    private let asphalt = Color(red: 0.153, green: 0.153, blue: 0.168)
    private let curb = Color.white.opacity(0.22)

    private var cardWidth: CGFloat { baseCardWidth * zoom }
    private var cardHeight: CGFloat { baseCardHeight * zoom }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy: a file with forty bays only builds the two you can see.
                LazyVStack(
                    alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]
                ) {
                    if lot.document.bays.isEmpty {
                        emptyLot
                    } else {
                        ForEach(Array(lot.document.bays.enumerated()), id: \.offset) { b, bay in
                            Section {
                                BayGrid(
                                    bay: b,
                                    bayName: bay.name,
                                    ideas: bay.ideas,
                                    cardWidth: cardWidth,
                                    cardHeight: cardHeight,
                                    gutter: gutter,
                                    zoom: zoom,
                                    onTap: { toggle($0) },
                                    onDrop: { ref in drop(ref, toBay: bay.name) }
                                )
                                .padding(.horizontal, edgePad)
                                .padding(.bottom, 18)
                            } header: {
                                baySign(b)
                                    .id(b)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(asphalt)
            .onChange(of: resetRequests) { _, _ in
                zoom = 1
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(0, anchor: .top) }
            }
            .onChange(of: jumpToBay) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                jumpToBay = nil
            }
        }
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
        .overlay { editor }
    }

    // MARK: - The open idea

    /// The idea you clicked, over a scrim. It used to reverse out into a lane
    /// below its stall, which meant the board reflowed around it every time.
    /// Floating it costs the board nothing.
    @ViewBuilder
    private var editor: some View {
        if let sel = selected, idea(sel) != nil {
            ZStack {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                IdeaPanel(
                    lot: lot, bay: sel.bay, idea: sel.idea,
                    onMoveToBay: { moveSelected(toBay: $0) },
                    onClose: { close() })
                    .id(sel)
                    .frame(maxWidth: 360)
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

    /// The sign over a bay: name on the left, count on the right, a painted
    /// rule under both. Double-click the name to rename the bay, which
    /// rewrites the `## ` heading in the file. It is opaque because it sticks
    /// to the top of the scroll and cards pass underneath it.
    @ViewBuilder
    private func baySign(_ b: Int) -> some View {
        if lot.document.bays.indices.contains(b) {
            let bay = lot.document.bays[b]
            let sign = Self.baySign(bay.name)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
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

/// One bay's cards, wrapping to fill the width.
///
/// Its own view for two reasons. The drop highlight lives in here, so dragging
/// a card across the board redraws one bay instead of the board. And an
/// adaptive grid fills whatever width it is given, so the cards are as dense as
/// the panel allows at any zoom, with no leftover strip down the side.
private struct BayGrid: View {
    let bay: Int
    let bayName: String
    let ideas: [ParkedIdea]
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let gutter: CGFloat
    let zoom: CGFloat
    let onTap: (ParkingLotView.IdeaRef) -> Void
    let onDrop: (ParkingLotView.IdeaRef) -> Void

    @State private var targeted = false

    var body: some View {
        Group {
            if ideas.isEmpty {
                Text("Nothing parked here. Drop a card, or use the plus.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cardWidth), spacing: gutter,
                                       alignment: .topLeading)],
                    alignment: .leading,
                    spacing: gutter
                ) {
                    ForEach(ideas.indices, id: \.self) { i in
                        IdeaCard(
                            ref: ParkingLotView.IdeaRef(bay: bay, idea: i),
                            title: ideas[i].title,
                            details: ideas[i].details,
                            color: Palette.card(ideas[i].color).color,
                            height: cardHeight,
                            zoom: zoom,
                            onTap: onTap
                        )
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

/// One idea. A filled rectangle and a line of text, nothing drawn, nothing
/// measured: the whole point of the rewrite is that a hundred of these cost
/// less than a dozen of the old canvas-drawn cars.
private struct IdeaCard: View {
    let ref: ParkingLotView.IdeaRef
    let title: String
    let details: String
    let color: Color
    let height: CGFloat
    let zoom: CGFloat
    let onTap: (ParkingLotView.IdeaRef) -> Void

    @State private var hovered = false

    var body: some View {
        Text(title.isEmpty ? "Untitled" : title)
            .font(.system(size: 11.5 * zoom, weight: .semibold))
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.leading)
            .foregroundStyle(Palette.cardInk.color)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(7 * zoom)
            .frame(height: height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
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
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(hovered ? 0.45 : 0.12), lineWidth: 1)
            )
            .scaleEffect(hovered ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { onTap(ref) }
            // The car survives as the thing you drag. It was the best part of
            // the old lot and it costs one sprite, once, mid-drag.
            .draggable(ref.payload) {
                CarSprite(color: color).frame(width: 78, height: 34)
            }
            .help(details.isEmpty ? (title.isEmpty ? "Untitled idea" : title)
                                  : "\(title)\n\n\(details)")
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
            // card shows. It is still just the first line of the markdown
            // bullet underneath.
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
