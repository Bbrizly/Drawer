import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let panel = DrawerPanel()
    private var transitionState = PanelTransitionState()
    var isShown: Bool { transitionState.isShown }
    private(set) var isExpanded = false

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
        panel.contentView = NSHostingView(rootView: rootView)
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

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let vf = screen.visibleFrame
        let inset: CGFloat = 12
        let height = isExpanded ? vf.height - inset * 2 : min(compactHeight, vf.height - inset * 2)
        return NSRect(
            x: vf.minX + inset,
            y: vf.maxY - inset - height, // anchored top-left
            width: width,
            height: height
        )
    }

    func show() {
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
    }

    func hide() {
        let hideGeneration = transitionState.beginHide()
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
