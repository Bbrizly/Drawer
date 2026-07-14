import AppKit
import DrawerCore
import SwiftUI

/// Point sizes for each sticky size (spec "Pull-out": full / title-only / chip).
/// The drawer slip is portrait; the pulled-out `.full` sticky is that slip
/// scaled up by `sticky.pullOutScale`, so the pull-out reads as the same paper
/// grown in the hand (flow c).
enum StickyMetrics {
    /// The portrait slip default, used when no tuned size is threaded in (bare
    /// tests). The live size comes from `sticky.slipWidth`/`slipHeight`.
    static let drawerSlip = CGSize(width: 96, height: 144)
    static let subtaskRowHeight: CGFloat = 16

    static func size(_ s: StickySize, pullOutScale: CGFloat = 1, slip: CGSize = drawerSlip) -> CGSize {
        switch s {
        case .full:
            return CGSize(width: slip.width * pullOutScale, height: slip.height * pullOutScale)
        case .title: return CGSize(width: slip.width, height: 46)
        case .chip: return CGSize(width: slip.width, height: 34)
        }
    }

    /// The panel size a model needs right now: the base slip (scaled for a
    /// `.full` pull-out) plus one row per visible subtask line (R3) and the
    /// "+N more" row. Only the `.full` size shows subtasks, so the others stay
    /// fixed.
    @MainActor
    static func size(for model: StickyModel) -> CGSize {
        var s = size(model.size, pullOutScale: CGFloat(model.pullOutScale), slip: model.slipSize)
        if model.size == .full {
            let rows = model.visibleSubtaskCount + (model.overflowCount > 0 ? 1 : 0)
            s.height += CGFloat(rows) * subtaskRowHeight
        }
        return s
    }
}

extension StickySize {
    /// Double-click cycle order (spec "Pull-out").
    var next: StickySize {
        switch self {
        case .full: return .title
        case .title: return .chip
        case .chip: return .full
        }
    }
}

/// The state a single sticky renders from, shared by the panel's `StickyView`
/// and the `StickyPanelManager`. Kept as a small `ObservableObject` so the view
/// re-renders on a size cycle while the manager resizes the panel and persists.
///
/// R3: title editing and subtasks live here. Edits commit through the manager
/// callbacks into `BureauFeature`, which writes back via `TodoStore.rename` /
/// `.setNote` (spec flow e). Subtasks are the task's note lines, so the array
/// here is a working copy; commit joins and writes the whole note.
@MainActor
final class StickyModel: ObservableObject {
    let receiptID: UUID
    @Published var title: String
    @Published var size: StickySize
    @Published var subtasks: [String] = []
    /// True once "+N more" was clicked; the note grows taller instead of
    /// scrolling (spec Decision 2). Reset by a size cycle.
    @Published var isExpanded = false
    var subtaskVisibleCap = 6
    /// How much bigger the `.full` pull-out is than the drawer slip, set at
    /// spawn from `sticky.pullOutScale`. Drives the panel size and the grow-in.
    var pullOutScale: Double = 1.5
    /// The drawer slip size, set at spawn from `sticky.slipWidth`/`slipHeight`.
    var slipSize: CGSize = StickyMetrics.drawerSlip
    /// The grow-from-slip spring and its start scale, set at spawn from tuning.
    var growSpringResponse: Double = 0.28
    var growSpringDamping: Double = 0.72
    var growStart: Double = 0.667
    /// True only for a sticky just pulled out of the drawer, so `StickyView`
    /// plays the grow-from-slip animation once. A restored sticky opens at size.
    var growsIn = false

    /// Ink landed by the stamp arm (R4): the label, its baked rotation, and
    /// the double-strike ghost offset, chosen once at slam time.
    struct AppliedStamp {
        let kind: StampKind
        let rotationDeg: Double
        let ghostOffsetPx: Double
    }

    @Published var stamp: AppliedStamp?

    /// Set by the manager: resize the panel and persist the new size.
    var onResize: ((StickySize) -> Void)?
    /// Set by the manager: send this receipt back into the drawer.
    var onReturnHome: (() -> Void)?
    /// Set by the manager: the visible row count changed, refit the panel.
    var onLayoutChanged: (() -> Void)?
    /// Set by the manager: commit an edited title / the subtask lines.
    var onCommitTitle: ((String) -> Void)?
    var onCommitSubtasks: (([String]) -> Void)?

    /// The last title known to be in Drawer.md, restored when an edit commits
    /// empty so the sticky never shows a blank slip.
    private var committedTitle: String

    init(receiptID: UUID, title: String, size: StickySize) {
        self.receiptID = receiptID
        self.title = title
        self.size = size
        self.committedTitle = title
    }

    /// Double-click advances the size and tells the manager to resize.
    func cycleSize() {
        size = size.next
        isExpanded = false
        onResize?(size)
    }

    // MARK: R3 edits

    var visibleSubtaskCount: Int {
        guard size == .full else { return 0 }
        return isExpanded ? subtasks.count : min(subtasks.count, max(1, subtaskVisibleCap))
    }

    var overflowCount: Int { size == .full ? subtasks.count - visibleSubtaskCount : 0 }

    func expand() {
        isExpanded = true
        onLayoutChanged?()
    }

    func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            title = committedTitle
            return
        }
        title = trimmed
        committedTitle = trimmed
        onCommitTitle?(trimmed)
    }

    /// Cleans the working lines (an emptied row is a delete) and writes the
    /// note back. Layout refits because the row count may have changed.
    func commitSubtasks() {
        subtasks = subtasks
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onCommitSubtasks?(subtasks)
        onLayoutChanged?()
    }

    func addSubtask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        subtasks.append(trimmed)
        commitSubtasks()
    }
}

/// The floating sticky note: the receipt as a manipulable paper slip in the
/// Bureau palette (cream, one red rule, big pixel title) with a torn top edge
/// echoing the drawer slip, a double-click size cycle, and a return-home
/// affordance. R3: a single click on the title edits it in place, and the
/// `.full` size lists the task's note lines as subtasks, each editable, with
/// a "+N more" row that grows the note taller (never scrolls) and an add row.
struct StickyView: View {
    @ObservedObject var model: StickyModel

    @State private var isEditingTitle = false
    @State private var newSubtask = ""
    @State private var grown = false
    @FocusState private var titleFocused: Bool

    private var metrics: CGSize { StickyMetrics.size(for: model) }
    private var titleFontSize: CGFloat { model.size == .chip ? 11 : 15 }
    /// The scale a freshly pulled-out sticky starts at: the tuned start (about
    /// the drawer slip relative to the grown pull-out) so it swells up out of
    /// the drawer.
    private var growStart: CGFloat {
        guard model.growsIn, model.size == .full else { return 1 }
        return CGFloat(model.growStart)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            paper
            content
            returnHomeButton
                .padding(4)
                .opacity(model.size == .chip ? 0 : 1) // no room on a chip
            if let stamp = model.stamp {
                StampInkView(stamp: stamp)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .contentShape(Rectangle())
        .scaleEffect(grown ? 1 : growStart)
        // Double-click cycles the size (spec "Pull-out"); a single click on the
        // title starts editing instead (R3).
        .onTapGesture(count: 2) { model.cycleSize() }
        .help(BureauCopy.stickySizeCycleHint)
        .onAppear {
            // A pulled-out sticky swells from the drawer-slip scale up to full;
            // any other spawn (restore at launch) just opens at size.
            if model.growsIn, model.size == .full {
                withAnimation(.spring(response: model.growSpringResponse, dampingFraction: model.growSpringDamping)) { grown = true }
            } else {
                grown = true
            }
        }
    }

    // MARK: paper

    private var paper: some View {
        TornSlip()
            .fill(Color(nsColor: BureauPalette.cream))
            .overlay(
                TornSlip()
                    .fill(Color(nsColor: BureauPalette.creamShade).opacity(0.5))
                    .mask {
                        VStack(spacing: 0) {
                            Spacer()
                            Rectangle().frame(height: metrics.height * 0.28)
                        }
                    }
            )
            .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch model.size {
        case .full:
            VStack(alignment: .leading, spacing: 4) {
                titleText(lineLimit: 3)
                Rectangle()
                    .fill(Color(nsColor: BureauPalette.red))
                    .frame(height: 1.5)
                subtaskRows
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        case .title:
            titleText(lineLimit: 2)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .chip:
            titleText(lineLimit: 1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func titleText(lineLimit: Int) -> some View {
        if isEditingTitle {
            TextField("", text: $model.title)
                .textFieldStyle(.plain)
                .font(.custom(BureauPalette.pixelFamily, size: titleFontSize))
                .foregroundStyle(Color(nsColor: BureauPalette.ink))
                .focused($titleFocused)
                .onSubmit { endTitleEdit() }
                .onChange(of: titleFocused) { _, focused in
                    if !focused { endTitleEdit() }
                }
        } else {
            Text(model.title)
                .font(.custom(BureauPalette.pixelFamily, size: titleFontSize))
                .foregroundStyle(Color(nsColor: BureauPalette.ink))
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditingTitle = true
                    titleFocused = true
                }
        }
    }

    private func endTitleEdit() {
        guard isEditingTitle else { return }
        isEditingTitle = false
        model.commitTitle()
    }

    // MARK: subtasks (R3)

    private var subtaskRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<model.visibleSubtaskCount, id: \.self) { i in
                TextField("", text: $model.subtasks[i])
                    .textFieldStyle(.plain)
                    .font(.custom(BureauPalette.pixelFamily, size: 10))
                    .foregroundStyle(Color(nsColor: BureauPalette.ink))
                    .onSubmit { model.commitSubtasks() }
                    .frame(height: StickyMetrics.subtaskRowHeight - 2)
            }
            if model.overflowCount > 0 {
                Button(action: { model.expand() }) {
                    Text(BureauCopy.subtasksOverflow(model.overflowCount))
                        .font(.custom(BureauPalette.pixelFamily, size: 10))
                        .foregroundStyle(Color(nsColor: BureauPalette.inkFaint))
                }
                .buttonStyle(.plain)
                .frame(height: StickyMetrics.subtaskRowHeight - 2)
            }
            TextField(BureauCopy.addSubtaskPlaceholder, text: $newSubtask)
                .textFieldStyle(.plain)
                .font(.custom(BureauPalette.pixelFamily, size: 10))
                .foregroundStyle(Color(nsColor: BureauPalette.inkFaint))
                .onSubmit {
                    model.addSubtask(newSubtask)
                    newSubtask = ""
                }
                .frame(height: StickyMetrics.subtaskRowHeight - 2)
        }
    }

    private var returnHomeButton: some View {
        Button(action: { model.onReturnHome?() }) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: BureauPalette.inkFaint))
                .padding(3)
                .background(Circle().fill(Color(nsColor: BureauPalette.cream)))
        }
        .buttonStyle(.plain)
        .help(BureauCopy.exitModeButtonTooltip)
    }
}

/// Stamped ink (R4): the label in a rough box, rotated the few degrees the
/// slam landed at, over a lighter double-strike ghost. It scales in hard from
/// oversize so the arrival reads as the 12-frame slam, not a fade.
struct StampInkView: View {
    let stamp: StickyModel.AppliedStamp

    @State private var landed = false

    var body: some View {
        ZStack {
            inkFace(opacity: 0.25)
                .offset(x: stamp.ghostOffsetPx, y: stamp.ghostOffsetPx)
            inkFace(opacity: 0.85)
        }
        .rotationEffect(.degrees(stamp.rotationDeg))
        .scaleEffect(landed ? 1 : 2.4)
        .opacity(landed ? 1 : 0)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeIn(duration: 0.08)) { landed = true }
        }
    }

    private func inkFace(opacity: Double) -> some View {
        Text(stamp.kind.label)
            .font(.custom(BureauPalette.pixelFamily, size: 16))
            .fontWeight(.black)
            .foregroundStyle(Color(nsColor: stamp.kind.color).opacity(opacity))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Rectangle()
                    .strokeBorder(Color(nsColor: stamp.kind.color).opacity(opacity), lineWidth: 2)
            )
    }
}

/// A rectangle with a shallow jagged tear along the top edge, echoing the baked
/// tear on the drawer slip so the handoff into a sticky reads as the same paper.
/// Deterministic, so the note never re-shuffles its teeth on a redraw.
private struct TornSlip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth = 12
        let dx = rect.width / CGFloat(teeth)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + 3))
        for i in 0...teeth {
            let x = rect.minX + CGFloat(i) * dx
            let y = rect.minY + (i.isMultiple(of: 2) ? 0 : 3)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
