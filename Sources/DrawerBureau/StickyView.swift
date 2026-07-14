import AppKit
import DrawerCore
import SwiftUI

/// Point sizes for each sticky size (spec "Pull-out": full / title-only / chip).
/// `full` matches the drawer slip exactly so the drag handoff (flow c) reads as
/// one object: the panel spawns at the same size the sprite showed.
enum StickyMetrics {
    static let fullSlip = CGSize(width: 150, height: 84)

    static func size(_ s: StickySize) -> CGSize {
        switch s {
        case .full: return fullSlip
        case .title: return CGSize(width: 150, height: 46)
        case .chip: return CGSize(width: 112, height: 34)
        }
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
/// R3 hook: title editing and subtasks land here. Add `@Published var isEditing`
/// and an `onCommitTitle: (String) -> Void` (wired to `TodoStore.rename`), then
/// swap the title `Text` in `StickyView` for a `TextField($model.title)`; add a
/// `@Published var subtaskLines: [String]` rendered under the title in the
/// `.full` body. No structural change to the panel or the manager is needed.
@MainActor
final class StickyModel: ObservableObject {
    let receiptID: UUID
    @Published var title: String
    @Published var size: StickySize

    /// Set by the manager: resize the panel and persist the new size.
    var onResize: ((StickySize) -> Void)?
    /// Set by the manager: send this receipt back into the drawer.
    var onReturnHome: (() -> Void)?

    init(receiptID: UUID, title: String, size: StickySize) {
        self.receiptID = receiptID
        self.title = title
        self.size = size
    }

    /// Double-click advances the size and tells the manager to resize.
    func cycleSize() {
        size = size.next
        onResize?(size)
    }
}

/// The floating sticky note. R2 shell: it shows the receipt as a manipulable
/// paper slip in the Bureau palette (cream, one red rule, big pixel title) with
/// a torn top edge echoing the drawer slip, a double-click size cycle, and a
/// return-home affordance. No text editing and no subtasks yet; those are R3
/// and slot into `StickyModel` (see its doc) without touching this layout.
struct StickyView: View {
    @ObservedObject var model: StickyModel

    private var metrics: CGSize { StickyMetrics.size(model.size) }
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
        // Double-click cycles the size (spec "Pull-out"). A single click is left
        // free so R3 can start title editing on it.
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
                // R3 hook: subtask lines render here, capped at
                // tuning.sticky.subtaskVisibleCap with a "+N more" row.
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

    private func titleText(lineLimit: Int) -> some View {
        Text(model.title)
            .font(.custom(BureauPalette.pixelFamily, size: titleFontSize))
            .foregroundStyle(Color(nsColor: BureauPalette.ink))
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
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
