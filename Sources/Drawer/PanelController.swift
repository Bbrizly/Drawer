import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    /// Posted when the drawer panel slides into view (hotkey, tap, or menu).
    static let drawerDidOpen = Notification.Name("drawerDidOpen")
}

@MainActor
final class PanelController {
    private let panel = DrawerPanel()
    private let hosting: NSHostingView<AnyView>
    private var transitionState = PanelTransitionState()
    var isShown: Bool { transitionState.isShown }
    // Backed by UserDefaults so the drawer's expand button can watch the same
    // key via @AppStorage and flip its icon.
    private var isExpanded: Bool {
        get { UserDefaults.standard.bool(forKey: "drawerExpanded") }
        set { UserDefaults.standard.set(newValue, forKey: "drawerExpanded") }
    }
    /// Fired with true on show, false on hide. Lets the timers park their
    /// display tickers while the panel is hidden (SwiftUI's onDisappear does
    /// not fire reliably on orderOut, so this is the authoritative signal).
    var onVisibilityChange: ((Bool) -> Void)?
    private var boardCoverage: CGFloat = 0   // 0 = normal panel, 1 = full screen
    private var isPaneOpen = false           // companion pane grows the panel right

    /// The companion pane's fixed column width. Kept in sync with
    /// `CompanionPaneView`'s frame.
    static let paneWidth: CGFloat = 320

    // Defaults are registered at launch, so plain reads are safe.
    private var width: CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: "panelWidth"))
    }
    private var compactHeight: CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: "panelCompactHeight"))
    }
    private var shouldReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    /// Toggle slide duration, tunable in Settings. Reduce-motion forces instant.
    private var slideDuration: Double {
        shouldReduceMotion ? 0 : UserDefaults.standard.double(forKey: "panelSlideDuration")
    }

    /// Snappy ease-out for slide-in; tuned for short UI motion.
    private static let showTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
    /// Quick ease-in for slide-out.
    private static let hideTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)

    init<V: View>(rootView: V) {
        let hosting = NSHostingView(rootView: AnyView(rootView))
        // This controller owns the panel's frame. Empty sizing options stop
        // SwiftUI content minimums from resizing the window (a wide header
        // pill, say the Work Mode card, must truncate, never push the panel
        // wider than the width set in Settings).
        hosting.sizingOptions = []
        // The closed companion pane is laid out past the window edge and must not paint outside it.
        hosting.clipsToBounds = true
        // Layer-back the content so the show/hide slide (a window-origin move)
        // composites on the GPU. Keep the default redraw policy (.duringViewResize):
        // .onSetNeedsDisplay would stretch a stale bitmap during the width-changing
        // pane-open / expand / board-swipe animations, which resize this view.
        hosting.wantsLayer = true
        self.hosting = hosting
        panel.contentView = hosting
    }

    func toggle() {
        isShown ? hide() : show()
    }

    /// Makes the panel the key window so text fields actually receive
    /// keystrokes. Without this, programmatically-focused fields can leave
    /// typing going to the previously active app (the panel is
    /// non-activating and only becomes key on direct text-field clicks).
    func makeKeyIfShown() {
        guard isShown else { return }
        panel.makeKey()
    }

    /// True when the drawer panel itself is the key window.
    var isPanelKey: Bool { panel.isKeyWindow }

    /// Re-applies the target frame in place (settings sliders).
    func refreshFrame() {
        guard isShown else { return }
        panel.setFrame(targetFrame(), display: true)
    }

    /// Compact: small card pinned top-left. Expanded: full screen height.
    func toggleSize() {
        isExpanded.toggle()
        guard isShown else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shouldReduceMotion ? 0 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame(), display: true)
        }
    }

    /// Opens or closes the companion pane column, animating the panel wider or
    /// back. Driven by `PaneRouter.activePane` via the drawer view.
    func setPaneOpen(_ open: Bool) {
        guard isPaneOpen != open else { return }
        isPaneOpen = open
        guard isShown else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shouldReduceMotion ? 0 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame(), display: true)
        }
    }

    /// How much of the screen the board covers: 0 = normal panel, 1 = full
    /// screen. Driven by the swipe amount, so the user dials in the coverage.
    func setBoardCoverage(_ coverage: CGFloat) {
        let clamped = max(0, min(1, coverage))
        guard boardCoverage != clamped else { return }
        boardCoverage = clamped
        guard isShown else { return }
        // Instant (no animation) so the panel tracks the live swipe, not lags it.
        panel.setFrame(targetFrame(), display: true)
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        // visibleFrame, not frame -- menu bar and dock eat into the latter
        let vf = screen.visibleFrame
        let inset: CGFloat = 12
        let normalH = isExpanded ? vf.height - inset * 2 : min(compactHeight, vf.height - inset * 2)
        // Grow rightward for the companion pane, but never off the screen: clamp
        // the total to the visible width so a narrow display / Stage Manager /
        // external monitor still fits.
        let desiredWidth = width + (isPaneOpen ? Self.paneWidth : 0)
        let maxWidth = vf.width - inset * 2
        let normal = NSRect(
            x: vf.minX + inset,
            y: vf.maxY - inset - normalH, // anchored top-left
            width: min(desiredWidth, maxWidth),
            height: normalH
        )
        guard boardCoverage > 0 else { return normal }
        let full = vf.insetBy(dx: inset, dy: inset)
        let t = boardCoverage
        return NSRect(
            x: normal.minX + (full.minX - normal.minX) * t,
            y: normal.minY + (full.minY - normal.minY) * t,
            width: normal.width + (full.width - normal.width) * t,
            height: normal.height + (full.height - normal.height) * t
        )
    }

    /// Park the panel fully off the left edge, ready to slide in.
    private func offScreenOrigin(for frame: NSRect, hiding: Bool) -> NSPoint {
        NSPoint(
            x: frame.origin.x - frame.width - (hiding ? 36 : 24),
            y: frame.origin.y
        )
    }

    func show() {
        if UserDefaults.standard.bool(forKey: "startExpanded") { isExpanded = true }
        let target = targetFrame()
        guard target != .zero else { return }
        var start = target
        start.origin = offScreenOrigin(for: target, hiding: false)
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = slideDuration
            ctx.timingFunction = Self.showTiming
            panel.animator().setFrame(target, display: true)
        }
        transitionState.beginShow()
        onVisibilityChange?(true)
        NotificationCenter.default.post(name: .drawerDidOpen, object: nil)
    }

    func hide() {
        let hideGeneration = transitionState.beginHide()
        onVisibilityChange?(false)
        var off = panel.frame
        off.origin = offScreenOrigin(for: panel.frame, hiding: true)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = slideDuration
            ctx.timingFunction = Self.hideTiming
            panel.animator().setFrame(off, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.transitionState.shouldOrderOut(hideGeneration: hideGeneration)
                else {
                    return
                }
                self.panel.orderOut(nil)
            }
        })
    }
}
