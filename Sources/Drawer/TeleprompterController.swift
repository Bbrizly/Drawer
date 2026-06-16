import AppKit
import DrawerCore
import SwiftUI

/// Owns the teleprompter window: a borderless panel parked top-center of the
/// screen that floats above everything, including full-screen apps. One per
/// app, toggled from the notes pad.
@MainActor
final class TeleprompterController {
    private let store: NotesStore
    private var panel: NSPanel?

    var isShown: Bool { panel != nil }

    init(store: NotesStore) {
        self.store = store
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 280),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // One step above the drawer so it reads over the panel and other apps.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true // drag it anywhere by the body

        let view = TeleprompterView(store: store, onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Centers horizontally, pinned near the top under the menu bar.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height // flush against the top of the usable area
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
