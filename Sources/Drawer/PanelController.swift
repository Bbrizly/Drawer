import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel = DrawerPanel()
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

    init<V: View>(rootView: V) {
        let hosting = NSHostingView(rootView: rootView)
        // This controller owns the panel's frame. Empty sizing options stop
        // SwiftUI content minimums from resizing the window (a wide header
        // pill, say the Work Mode card, must truncate, never push the panel
        // wider than the width set in Settings).
        hosting.sizingOptions = []
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
        let normal = NSRect(
            x: vf.minX + inset,
            y: vf.maxY - inset - normalH, // anchored top-left
            width: width,
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

    func show() {
        if UserDefaults.standard.bool(forKey: "startExpanded") { isExpanded = true }
        let target = targetFrame()
        guard target != .zero else { return }
        var start = target
        start.origin.x -= width + 24
        panel.setFrame(start, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shouldReduceMotion ? 0 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
        transitionState.beginShow()
        onVisibilityChange?(true)
    }

    func hide() {
        let hideGeneration = transitionState.beginHide()
        onVisibilityChange?(false)
        var off = panel.frame
        off.origin.x -= width + 36
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = shouldReduceMotion ? 0 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().setFrame(off, display: true)
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
