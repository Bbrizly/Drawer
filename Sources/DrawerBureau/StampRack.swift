import AppKit
import SwiftUI

/// The two stamps (spec "The stamp"): green APPROVED files the task, red
/// DENIED sends the receipt back to the pile. The kinds stay `.done`/
/// `.postponed` internally; only the labels changed to the Papers-Please
/// wording (`BureauCopy`).
enum StampKind {
    case done
    case postponed

    var label: String {
        switch self {
        case .done: return BureauCopy.doneStampLabel
        case .postponed: return BureauCopy.postponedStampLabel
        }
    }

    var color: NSColor {
        switch self {
        case .done: return BureauPalette.stampGreen
        case .postponed: return BureauPalette.red
        }
    }
}

/// The stamp rack (spec "The stamp"). A small vertical tab is pinned at the
/// right screen edge whenever a sticky is live. Pressing its arrow slides a
/// panel out leftward revealing two stamp heads seen from above, APPROVED and
/// DENIED. You drag a sticky under the head you want and click the head: it
/// presses straight down, and at the bottom of the press the topmost live
/// sticky whose window intersects the head's footprint gets stamped.
///
/// Replaces the old sweep arm: no cursor zone, no poll, no summon buttons. The
/// tab is the only affordance, always in the same spot, so the mechanism is
/// discoverable but stays out of the way.
@MainActor
final class StampController {
    /// Set by the facade: the live sticky windows to hit-test, front-to-back.
    var stickyFrames: (() -> [(id: UUID, frame: NSRect)])?
    /// Set by the facade: the slam landed on a sticky (show ink, thunk, haptic).
    var onSlam: ((UUID, StampKind) -> Void)?
    /// Set by the facade: the head lifted, apply the consequence.
    var onStamp: ((UUID, StampKind) -> Void)?
    /// Set by the facade: the head pressed onto nothing, a soft thunk only.
    var onPressMiss: (() -> Void)?
    /// Set by the facade: the live rack geometry and press timings.
    var tuningProvider: (() -> BureauStampTuning)?

    // Geometry and press timings, read live from tuning so a slider edit
    // reshapes the rack on its next build.
    private var stamp: BureauStampTuning { tuningProvider?() ?? BureauTuningDocument.defaults.stamp }
    private var rackWidthPx: CGFloat { CGFloat(stamp.rackWidthPx) }
    private var stampSizePx: CGFloat { CGFloat(stamp.stampSizePx) }
    private var extendMs: Double { stamp.extendMs }
    private var pressMs: Double { stamp.pressMs }
    private var liftMs: Double { stamp.liftMs }

    private let tabWidth: CGFloat = 30
    private let rackHeight: CGFloat = 130

    private var rackPanel: NSPanel?
    private var expanded = false
    private var watching = false
    /// The sticky a press landed on, stamped once the head lifts.
    private var pendingStamp: (id: UUID, kind: StampKind)?

    /// Shows the rack tab while any sticky is live, hides it otherwise. Reuses
    /// the facade's live-count wiring; no timer, the tab just sits there.
    func setWatching(_ watching: Bool) {
        self.watching = watching
        if watching {
            if rackPanel == nil { buildRack() }
        } else {
            hideRack()
        }
    }

    // MARK: the rack panel

    private func buildRack() {
        guard let screen = NSScreen.main else { return }
        let frame = rackFrame(on: screen, expanded: expanded)
        let panel = makeOverlayPanel(frame: frame)
        panel.contentView = NSHostingView(rootView: rackView())
        panel.orderFrontRegardless()
        rackPanel = panel
    }

    private func hideRack() {
        rackPanel?.orderOut(nil)
        rackPanel = nil
        expanded = false
        pendingStamp = nil
    }

    /// Extends or retracts the rack. Resizing the panel (rather than a single
    /// always-wide window) keeps the collapsed tab from intercepting clicks
    /// across the whole right edge.
    private func toggleExpanded() {
        guard let panel = rackPanel, let screen = NSScreen.main else { return }
        expanded.toggle()
        let frame = rackFrame(on: screen, expanded: expanded)
        panel.contentView = NSHostingView(rootView: rackView())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = extendMs / 1000
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func rackFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let vis = screen.visibleFrame
        let width = expanded ? tabWidth + rackWidthPx : tabWidth
        let y = vis.midY - rackHeight / 2
        return NSRect(x: vis.maxX - width, y: y, width: width, height: rackHeight)
    }

    private func rackView() -> some View {
        StampRackView(
            expanded: expanded,
            tabWidth: tabWidth,
            rackWidth: rackWidthPx,
            height: rackHeight,
            stampSize: stampSizePx,
            headCenter: { [weak self] in self?.headContentCenter($0) ?? .zero },
            pressMs: pressMs,
            liftMs: liftMs,
            onToggle: { [weak self] in self?.toggleExpanded() },
            onPressBottom: { [weak self] kind in self?.pressBottom(kind) },
            onLifted: { [weak self] kind in self?.lifted(kind) }
        )
    }

    // MARK: head geometry (shared by the view and the hit-test)

    /// A stamp head's center in the panel content's top-left coordinate space,
    /// so the SwiftUI layout and the screen hit-test agree on where each head
    /// sits. APPROVED sits left, DENIED right, in the rack area beside the tab.
    private func headContentCenter(_ kind: StampKind) -> CGPoint {
        let x = kind == .done ? rackWidthPx * 0.30 : rackWidthPx * 0.70
        return CGPoint(x: x, y: rackHeight * 0.40)
    }

    /// The head's footprint in screen coordinates: the square directly under
    /// the head that a sticky must overlap to get stamped. Flips the content's
    /// top-left y into the window's bottom-left y.
    private func footprintScreenRect(_ kind: StampKind) -> NSRect {
        guard let panel = rackPanel else { return .zero }
        let c = headContentCenter(kind)
        let screenX = panel.frame.minX + c.x
        let screenY = panel.frame.maxY - c.y
        return NSRect(
            x: screenX - stampSizePx / 2, y: screenY - stampSizePx / 2,
            width: stampSizePx, height: stampSizePx
        )
    }

    // MARK: press -> stamp

    /// The head reached the bottom of its press. Find the topmost live sticky
    /// under the footprint and slam it; else a soft thunk onto nothing.
    private func pressBottom(_ kind: StampKind) {
        let footprint = footprintScreenRect(kind)
        guard let hit = (stickyFrames?() ?? []).first(where: { $0.frame.intersects(footprint) }) else {
            onPressMiss?()
            pendingStamp = nil
            return
        }
        pendingStamp = (hit.id, kind)
        onSlam?(hit.id, kind)
    }

    /// The head lifted back up. Apply the consequence to whatever the press
    /// landed on (nothing if it missed).
    private func lifted(_ kind: StampKind) {
        guard let pending = pendingStamp else { return }
        pendingStamp = nil
        onStamp?(pending.id, pending.kind)
    }

    private func makeOverlayPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the stickies so the head presses over the note it stamps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

/// The rack: a right-edge tab with a chevron and, when extended, two stamp
/// heads seen from above. The heads are positioned from the controller's shared
/// geometry so the drawn head lines up with the screen footprint it stamps.
private struct StampRackView: View {
    let expanded: Bool
    let tabWidth: CGFloat
    let rackWidth: CGFloat
    let height: CGFloat
    let stampSize: CGFloat
    let headCenter: (StampKind) -> CGPoint
    let pressMs: Double
    let liftMs: Double
    var onToggle: () -> Void
    var onPressBottom: (StampKind) -> Void
    var onLifted: (StampKind) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if expanded {
                head(.done)
                head(.postponed)
            }
            tab
                .frame(width: tabWidth, height: height)
                .position(x: (expanded ? rackWidth : 0) + tabWidth / 2, y: height / 2)
        }
        .frame(width: (expanded ? rackWidth : 0) + tabWidth, height: height)
    }

    private var tab: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: BureauPalette.tray))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(nsColor: BureauPalette.drawerLip), lineWidth: 1)
                    )
                Image(systemName: expanded ? "chevron.right" : "chevron.left")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(nsColor: BureauPalette.trayInk))
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: -1)
        }
        .buttonStyle(.plain)
        .help(expanded ? "Close the stamp rack" : "Open the stamp rack")
    }

    private func head(_ kind: StampKind) -> some View {
        let c = headCenter(kind)
        return StampHeadView(
            kind: kind, size: stampSize, pressMs: pressMs, liftMs: liftMs,
            onPressBottom: { onPressBottom(kind) },
            onLifted: { onLifted(kind) }
        )
        .position(x: c.x, y: c.y)
    }
}

/// A single stamp head seen from above: a die face carrying its word, with a
/// short caption below. Clicking it presses the head straight down (a small
/// drop plus a scale-up-then-flatten and a growing shadow, so it reads as
/// pressing onto the desk), fires at the bottom, then springs back and lifts.
private struct StampHeadView: View {
    let kind: StampKind
    let size: CGFloat
    let pressMs: Double
    let liftMs: Double
    var onPressBottom: () -> Void
    var onLifted: () -> Void

    /// 0 fully up, 1 fully pressed.
    @State private var depth: CGFloat = 0
    @State private var busy = false

    var body: some View {
        Button(action: press) {
            VStack(spacing: 4) {
                die
                Text(kind.label)
                    .font(.custom(BureauPalette.pixelFamily, size: 9))
                    .foregroundStyle(Color(nsColor: BureauPalette.trayInk))
            }
        }
        .buttonStyle(.plain)
        .help(kind.label)
    }

    private var die: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(nsColor: kind.color))
            .frame(width: size, height: size)
            .overlay(
                Text(kind.label)
                    .font(.custom(BureauPalette.pixelFamily, size: 11))
                    .fontWeight(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .foregroundStyle(Color(nsColor: BureauPalette.cream))
            )
            // The press: drop down, swell then flatten, shadow grows.
            .scaleEffect(x: 1 + depth * 0.06, y: 1 - depth * 0.12)
            .offset(y: depth * (size * 0.18))
            .shadow(color: .black.opacity(0.35), radius: 2 + depth * 8, y: 1 + depth * 3)
    }

    private func press() {
        guard !busy else { return }
        busy = true
        withAnimation(.easeIn(duration: pressMs / 1000)) { depth = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + pressMs / 1000) {
            onPressBottom()
            withAnimation(.easeOut(duration: liftMs / 1000)) { depth = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + liftMs / 1000) {
                onLifted()
                busy = false
            }
        }
    }
}
