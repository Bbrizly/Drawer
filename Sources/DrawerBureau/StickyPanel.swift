import AppKit
import SwiftUI

/// What the `StickyPanelManager` needs from a live sticky, abstracted so tests
/// can stand in a plain fake and drive the cap / state-transition logic with no
/// window server (the real one is `StickyPanel`). Origins and sizes are in
/// screen points; `hostWindow` is the real `NSWindow` the hover-scroll mover
/// moves, `nil` for a fake.
@MainActor
protocol StickyPanelHosting: AnyObject {
    var receiptID: UUID { get }
    var frameOrigin: CGPoint { get set }
    var contentSize: CGSize { get set }
    var hostWindow: NSWindow? { get }
    func present()
    func dismiss()
}

/// A single floating sticky note window. A non-activating `NSPanel` built on the
/// exact `TeleprompterController` recipe (borderless, `.nonactivatingPanel`,
/// `isFloatingPanel`, level floating+1, clear background, shadow,
/// `hidesOnDeactivate = false`) so it floats over the app without ever stealing
/// key focus from whatever you are actually typing in (spec risk 8). It hosts a
/// `StickyView` and does nothing else; movement (hover-scroll, drag handoff),
/// caps, and persistence all live in the manager.
/// A borderless panel cannot become key by default, but R3's in-place editing
/// needs the caret. `becomesKeyOnlyIfNeeded` keeps the manipulation gestures
/// (hover-scroll, drag, size cycle) from stealing key; only clicking a text
/// field takes it, and `.nonactivatingPanel` means even that never activates
/// the app (spec risk 8).
private final class KeyableStickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class StickyPanel: StickyPanelHosting {
    let receiptID: UUID
    private let panel: NSPanel

    init(receiptID: UUID, model: StickyModel, origin: CGPoint, size: CGSize) {
        self.receiptID = receiptID
        panel = KeyableStickyPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // One step above the drawer, matching the teleprompter, so a sticky sits
        // over the panel and other apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Movement is the hover-scroll gesture and the drag handoff, not a window
        // drag, so the body does not also move on a stray click-drag.
        panel.isMovableByWindowBackground = false

        let host = NSHostingView(rootView: StickyView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
    }

    var frameOrigin: CGPoint {
        get { panel.frame.origin }
        set { panel.setFrameOrigin(newValue) }
    }

    var contentSize: CGSize {
        get { panel.contentView?.frame.size ?? panel.frame.size }
        set {
            // Keep the top-left corner fixed so a resize grows/shrinks downward,
            // the way a note being folded down would read.
            let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            panel.setContentSize(newValue)
            panel.setFrameTopLeftPoint(topLeft)
        }
    }

    var hostWindow: NSWindow? { panel }

    func present() { panel.orderFrontRegardless() }
    func dismiss() { panel.orderOut(nil) }
}
