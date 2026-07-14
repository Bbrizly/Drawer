import AppKit
import DrawerCore
import SwiftUI

/// Point sizes for each sticky size (spec "Pull-out": full / title-only / chip).
/// `full` matches the drawer slip exactly so the drag handoff (flow c) reads as
/// one object: the panel spawns at the same size the sprite showed.
enum StickyMetrics {
    static let fullSlip = CGSize(width: 150, height: 84)
    static let subtaskRowHeight: CGFloat = 16

    static func size(_ s: StickySize) -> CGSize {
        switch s {
        case .full: return fullSlip
        case .title: return CGSize(width: 150, height: 46)
        case .chip: return CGSize(width: 112, height: 34)
        }
    }

    /// The panel size a model needs right now: the base slip plus one row per
    /// visible subtask line (R3) and the "+N more" row. The add row lives in
    /// the base slip's slack so a no-subtask sticky stays exactly the drawer
    /// slip size and the drag handoff reads as the same object. Only the
    /// `.full` size shows subtasks, so the others stay fixed.
    @MainActor
    static func size(for model: StickyModel) -> CGSize {
        var s = size(model.size)
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
    @FocusState private var titleFocused: Bool

    private var metrics: CGSize { StickyMetrics.size(for: model) }
    private var titleFontSize: CGFloat { model.size == .chip ? 11 : 15 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            paper
            content
            returnHomeButton
                .padding(4)
                .opacity(model.size == .chip ? 0 : 1) // no room on a chip
        }
        .frame(width: metrics.width, height: metrics.height)
        .contentShape(Rectangle())
        // Double-click cycles the size (spec "Pull-out"); a single click on the
        // title starts editing instead (R3).
        .onTapGesture(count: 2) { model.cycleSize() }
        .help(BureauCopy.stickySizeCycleHint)
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
