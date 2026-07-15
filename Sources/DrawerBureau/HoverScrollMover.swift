import AppKit

/// The signature interaction: while the cursor is over a live sticky, a
/// two-finger trackpad scroll MOVES the note instead of scrolling anything
/// (spec Decision 2, "hover-scroll move"). A single local `.scrollWheel`
/// monitor watches every scroll event; when one lands on a sticky panel it
/// nudges that window by the scroll delta and CONSUMES the event, so the
/// drawer's own `ScrollSwipeMonitor` never sees it and no board-page or
/// list-scroll fires underneath (spec risk 7).
///
/// The monitor is installed once the first sticky opens and removed when the
/// last one closes, so it costs nothing while no note is live. Because it is
/// installed at app launch (before the drawer's monitor appears on view
/// appear), it runs first and its `nil` return stops the event before the
/// drawer monitor is consulted.
///
/// Inertia is manual and deterministic: a physical scroll tracks the note 1:1
/// and seeds a velocity; on finger-up the note glides, decaying by
/// `inertiaFriction` each frame until it drops below `minDelta`. Trackpad
/// momentum events are consumed but not applied, so the OS glide and this one
/// never double up.
@MainActor
final class HoverScrollMover {
    private var token: Any?
    private var tuning: BureauHoverScrollTuning
    /// Resolves a scroll event to the sticky window under it, or `nil` if the
    /// scroll is not over a live sticky (then the event passes through).
    private let windowUnder: (NSEvent) -> NSWindow?
    /// Called when a move gesture settles, so the manager can persist the note's
    /// resting position.
    var onSettled: ((NSWindow) -> Void)?
    /// Keeps a moved note from gliding fully off-screen. Identity by default so
    /// the mover stays testable; the manager injects the real on-screen clamp.
    var clampOnScreen: (CGPoint, CGSize) -> CGPoint = { origin, _ in origin }

    private var inertiaTimer: Timer?
    private weak var glideWindow: NSWindow?
    private var velocity = CGVector.zero

    init(tuning: BureauHoverScrollTuning, windowUnder: @escaping (NSEvent) -> NSWindow?) {
        self.tuning = tuning
        self.windowUnder = windowUnder
    }

    func updateTuning(_ t: BureauHoverScrollTuning) { tuning = t }

    func start() {
        guard token == nil else { return }
        // Explicit guard, not `self?.handle(event) ?? event`: optional chaining
        // flattens the result, so a `nil` returned from `handle` to CONSUME the
        // event would be turned back into `event` by the `??` and passed through.
        // Consuming is the whole point here (risk 7), so return `handle`'s value
        // directly and only fall back to passing the event when self is gone.
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        stopInertia(settle: false)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = windowUnder(event) else { return event }

        // Physical scroll: track the note under the fingers and seed velocity.
        // Momentum events are swallowed (return nil below) but not applied.
        if event.momentumPhase == [] {
            stopInertia(settle: false)
            let dx = clamp(Double(event.scrollingDeltaX) * tuning.sensitivity)
            let dy = clamp(Double(event.scrollingDeltaY) * tuning.sensitivity)
            if abs(dx) >= tuning.minDelta || abs(dy) >= tuning.minDelta {
                // The note follows the fingers on x, but the y-axis is inverted
                // by request: scrolling the fingers up sends the note down. The
                // velocity is seeded with the same inverted dy so the inertia
                // glide keeps heading the way the note visibly moved.
                move(window, dx: dx, dy: -dy)
                velocity = CGVector(dx: dx, dy: -dy)
                glideWindow = window
            }
            if event.phase == .ended { startInertia() }
        }
        return nil // consume so the drawer swipe never sees it (risk 7)
    }

    private func clamp(_ v: Double) -> Double {
        max(-tuning.maxVelocity, min(tuning.maxVelocity, v))
    }

    private func move(_ window: NSWindow, dx: Double, dy: Double) {
        let before = window.frame.origin
        var o = before
        o.x += dx
        o.y += dy
        let after = clampOnScreen(o, window.frame.size)
        window.setFrameOrigin(after)

        // Keep the cursor on the note it is dragging: warp it by the delta the
        // window ACTUALLY moved (the clamp may have shrunk it at a screen edge).
        // Skip when the window did not move so a fully clamped scroll leaves the
        // pointer alone.
        guard tuning.cursorFollows else { return }
        let movedX = after.x - before.x
        let movedY = after.y - before.y
        if movedX == 0 && movedY == 0 { return }
        guard let primary = NSScreen.screens.first else { return }
        let target = Self.warpTarget(
            mouse: NSEvent.mouseLocation, dx: movedX, dy: movedY,
            primaryMaxY: primary.frame.maxY
        )
        CGWarpMouseCursorPosition(target)
        // Reassociate so the warp does not carry the OS input-suppression pause
        // that would otherwise freeze the pointer for a beat after each move.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// The AppKit mouse point plus a window delta, expressed in Quartz display
    /// space (top-left origin of the primary display) for `CGWarpMouseCursorPosition`.
    /// AppKit y grows up from the bottom, Quartz y grows down from the top, so
    /// the moved point flips against `primaryMaxY`.
    static func warpTarget(
        mouse: CGPoint, dx: CGFloat, dy: CGFloat, primaryMaxY: CGFloat
    ) -> CGPoint {
        CGPoint(x: mouse.x + dx, y: primaryMaxY - (mouse.y + dy))
    }

    private func startInertia() {
        stopInertia(settle: false)
        guard glideWindow != nil else { return }
        let friction = tuning.inertiaFriction
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let window = self.glideWindow else { timer.invalidate(); return }
                self.velocity.dx *= CGFloat(friction)
                self.velocity.dy *= CGFloat(friction)
                if hypot(self.velocity.dx, self.velocity.dy) < CGFloat(self.tuning.minDelta) {
                    self.stopInertia(settle: true)
                    return
                }
                self.move(window, dx: Double(self.velocity.dx), dy: Double(self.velocity.dy))
            }
        }
    }

    private func stopInertia(settle: Bool) {
        inertiaTimer?.invalidate()
        inertiaTimer = nil
        if settle, let window = glideWindow { onSettled?(window) }
        if settle { glideWindow = nil }
    }
}
