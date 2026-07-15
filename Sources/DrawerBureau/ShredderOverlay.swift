import AppKit
import SwiftUI

/// The screen-level shredder (R feedback 3): a small non-activating panel pinned
/// at the bottom-right of the main screen while any sticky is live, so a
/// pulled-out note can be shredded with the same drag it gets taken out with.
/// Modeled on `StampController`: the panel is the only affordance, always in the
/// same spot. Drops that land on it delete just the receipt, never the task,
/// exactly like the in-drawer shredder inside the scene.
@MainActor
final class ShredderController {
    /// Set by the facade: the live overlay geometry and the shred timing.
    var tuningProvider: (() -> BureauShredderTuning)?

    private var tuning: BureauShredderTuning { tuningProvider?() ?? BureauTuningDocument.defaults.shredder }
    private var overlayWidth: CGFloat { CGFloat(tuning.overlayWidthPx) }
    private var overlayHeight: CGFloat { CGFloat(tuning.overlayHeightPx) }

    /// Points of clearance from the screen's work area corner.
    private let margin: CGFloat = 16

    private var panel: NSPanel?
    private let state = ShredderState()
    private var watching = false
    /// Stickies mid-shred, retained so the window survives the slot animation
    /// after the manager has dropped it from its books.
    private var shredding: [StickyPanelHosting] = []

    /// Shows the shredder overlay while any sticky is live, hides it otherwise.
    /// Reuses the facade's live-count wiring next to the stamp rack. Shredding
    /// the last sticky drops the live count to zero while its slot animation is
    /// still running, so the panel stays up until the animation lands and only
    /// then hides (the completion handler checks `watching` again).
    func setWatching(_ watching: Bool) {
        self.watching = watching
        if watching {
            if panel == nil { buildPanel() }
        } else if shredding.isEmpty {
            hidePanel()
        }
    }

    // MARK: overlap (read by the settle path before the send-home check)

    /// True when a sticky window frame overlaps the shredder panel, so a drop
    /// that rests here shreds instead of going home or persisting in place.
    func overlaps(_ frame: NSRect) -> Bool {
        guard let panel else { return false }
        return panel.frame.intersects(frame)
    }

    /// A sticky moved: light the teeth while it hovers the slot so the target
    /// reads before release. Assigned only on change; every window move lands
    /// here, and an unconditional write would invalidate the overlay view (the
    /// publisher fires even for an equal value) on every mouse move.
    func stickyMoved(_ frame: NSRect) {
        let hovered = overlaps(frame)
        if hovered != state.hovered { state.hovered = hovered }
    }

    // MARK: shred

    /// Feeds a sticky into the slot: the receipt is already gone (the facade
    /// calls `shredReceipt` first); here the window shrinks and slides down into
    /// the slot over `shredMs`, then closes. The host is retained until the
    /// animation lands so it is not deallocated out from under the window.
    func shred(_ host: StickyPanelHosting) {
        state.hovered = false
        guard let window = host.hostWindow, let panel else {
            host.dismiss()
            return
        }
        shredding.append(host)
        let slot = slotRect(in: panel.frame)
        // The handler is @Sendable, so it may not capture the non-Sendable
        // host; carry its identity instead and look it up in `shredding` back
        // on the actor. AppKit always runs the handler on the main thread, so
        // the hop is `assumeIsolated` (same pattern as StickyPanelManager's
        // window observers).
        let hostID = ObjectIdentifier(host)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = max(0.05, tuning.shredMs / 1000)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(slot, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            MainActor.assumeIsolated {
                window?.alphaValue = 1
                guard let self else { return }
                if let index = self.shredding.firstIndex(where: { ObjectIdentifier($0) == hostID }) {
                    self.shredding.remove(at: index).dismiss()
                }
                // Shredding the last sticky turned watching off while this
                // animation ran; the panel was kept up so the slot stayed
                // visible. Hide it now that the last shred has landed.
                if !self.watching, self.shredding.isEmpty { self.hidePanel() }
            }
        })
    }

    /// A thin sliver at the slot mouth the sticky collapses into.
    private func slotRect(in frame: NSRect) -> NSRect {
        NSRect(x: frame.midX - 8, y: frame.minY + frame.height * 0.4, width: 16, height: 4)
    }

    // MARK: panel

    private func buildPanel() {
        guard let screen = NSScreen.main else { return }
        let panel = makeOverlayPanel(frame: panelFrame(on: screen))
        panel.contentView = NSHostingView(rootView: ShredderOverlayView(state: state))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        state.hovered = false
    }

    private func panelFrame(on screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        return NSRect(
            x: vis.maxX - overlayWidth - margin,
            y: vis.minY + margin,
            width: overlayWidth,
            height: overlayHeight
        )
    }

    private func makeOverlayPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Below the stamp rack but above the stickies, so a dropped note reads
        // as going over the slot.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // The overlay only shows the target; the drop lands through the settle
        // path, so the panel must not eat the mouse.
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// The teeth highlight, published so a drag over the slot lights it up without
/// rebuilding the whole panel view on every move.
@MainActor
private final class ShredderState: ObservableObject {
    @Published var hovered = false
}

/// The shredder seen from above: a dark slot with a row of teeth and a SHRED
/// caption, in the Bureau palette and pixel face, matching the in-drawer
/// shredder inside the scene.
private struct ShredderOverlayView: View {
    @ObservedObject var state: ShredderState

    private var teethColor: Color {
        Color(nsColor: state.hovered ? BureauPalette.stampGreen : BureauPalette.trayInk)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: BureauPalette.tray))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: BureauPalette.drawerLip), lineWidth: 1)
                )
            VStack(spacing: 5) {
                // The dark slot mouth with a row of teeth along its top lip.
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: BureauPalette.drawerLip))
                    HStack(spacing: 4) {
                        ForEach(0..<9, id: \.self) { _ in
                            Rectangle()
                                .fill(teethColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(height: 26)
                .padding(.horizontal, 10)
                Text(BureauCopy.shredderLabel)
                    .font(.custom(BureauPalette.pixelFamily, size: 10))
                    .foregroundStyle(teethColor)
            }
            .padding(.vertical, 8)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
