import AppKit

/// Listens for a whole shortcut while the user presses it: the modifiers as
/// they go down, then either the key that finishes the combination, or the
/// release of a lone modifier, which is a shortcut of its own.
/// Watches one press-and-release of a single modifier. A second modifier
/// joining, or any key press, means the user is building a combination and
/// this is not a lone tap.
struct LoneModifierTracker {
    private var first: UInt16?
    private var clean = false

    /// Feed it every modifier change: what is held now, and the key that
    /// moved. Returns the key code once a lone press and release completes.
    mutating func changed(flags: NSEvent.ModifierFlags, keyCode: UInt16) -> UInt16? {
        guard !flags.isEmpty else {
            defer {
                first = nil
                clean = false
            }
            return clean ? first : nil
        }
        if first == nil {
            first = keyCode
            clean = true
        } else if keyCode != first {
            clean = false
        }
        return nil
    }

    mutating func keyPressed() { clean = false }
}

@MainActor
final class HotkeyRecorder {
    private var monitor: Any?
    private var lone = LoneModifierTracker()

    /// `held` fires on every modifier change so a field can draw the keys as
    /// they are pressed. `capture` fires once, on whatever ends the shortcut.
    func start(
        held: @escaping (NSEvent.ModifierFlags) -> Void = { _ in },
        capture: @escaping (HotkeyBinding) -> Void
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return nil }
            if event.type == .flagsChanged {
                let flags = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting(.capsLock)
                held(flags)
                if let tapped = self.lone.changed(flags: flags, keyCode: event.keyCode) {
                    capture(.tap(UInt32(tapped)))
                }
                return nil
            }
            self.lone.keyPressed()
            capture(HotkeyBinding(event))
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        lone = LoneModifierTracker()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
