import AppKit
import SwiftUI

/// Shared swipe state for the rows, keyed by task id. Both inputs (mouse
/// click-drag and two-finger trackpad swipe) write here, so they can never
/// fight over a private per-row offset. Only one row is open at a time.
@MainActor
final class SwipeCoordinator: ObservableObject {
    let deleteWidth: CGFloat = 72
    /// How far a row slides right to reveal the in-progress affordance. Past
    /// half of this on release, the row is marked in progress and snaps back.
    let progressWidth: CGFloat = 72

    @Published private var offsets: [String: CGFloat] = [:]
    private(set) var openID: String?
    /// The row under the pointer. The scroll monitor swipes this one, so no
    /// hit-testing or coordinate conversion is needed.
    var hoveredID: String?
    /// Set once by the view. Called when a right swipe crosses the trigger
    /// threshold, with the row id, so the store can flip its in-progress flag.
    var onProgress: ((String) -> Void)?
    /// Feature flags. When a direction is off, the row can't slide that way and
    /// its action never fires, so both inputs (mouse and trackpad) honor it.
    var deleteEnabled = true
    var progressEnabled = true

    func offset(for id: String) -> CGFloat { offsets[id] ?? 0 }
    func isOpen(_ id: String) -> Bool { openID == id }

    /// Live tracking. `translationX` is cumulative from the gesture start
    /// (negative = swiping left to delete, positive = right to mark in
    /// progress), matching DragGesture's translation.
    func drag(id: String, translationX: CGFloat) {
        if let open = openID, open != id { offsets[open] = 0; openID = nil }
        let base: CGFloat = openID == id ? -deleteWidth : 0
        let lower: CGFloat = deleteEnabled ? -deleteWidth - 20 : 0
        let upper: CGFloat = progressEnabled ? progressWidth + 20 : 0
        offsets[id] = max(lower, min(upper, base + translationX))
    }

    /// Snap open or closed on release. A left swipe past half the delete width
    /// holds the delete button open. A right swipe past half the progress width
    /// fires the in-progress action and snaps the row back to rest.
    func end(id: String) {
        let off = offset(for: id)
        if deleteEnabled, off < -deleteWidth / 2 {
            offsets[id] = -deleteWidth
            openID = id
        } else if progressEnabled, off > progressWidth / 2 {
            offsets[id] = 0
            if openID == id { openID = nil }
            onProgress?(id)
        } else {
            offsets[id] = 0
            if openID == id { openID = nil }
        }
    }

    func close(id: String) {
        offsets[id] = 0
        if openID == id { openID = nil }
    }
}

/// Bridges two-finger trackpad horizontal scrolling into the swipe coordinator.
///
/// A local scroll-wheel monitor sees every scroll event. It locks the axis at
/// the start of each gesture: vertical gestures are returned untouched so the
/// task list scrolls as usual, horizontal gestures over the hovered row are
/// consumed and drive that row's swipe. So trackpad swipe, mouse drag, and
/// vertical scroll never clash.
@MainActor
final class ScrollSwipeMonitor: ObservableObject {
    private var token: Any?
    private weak var coordinator: SwipeCoordinator?
    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var axis: Axis?
    /// The row this gesture acts on, captured at .began. Held for the whole
    /// gesture so a mid-gesture reorder (an in-progress row jumping to the top)
    /// can never retarget the swipe to a different task.
    private var lockedID: String?
    /// The physical swipe already settled. Trailing inertial momentum must not
    /// re-drive the offset or fire the action a second time.
    private var settled = false

    private enum Axis { case horizontal, vertical }

    func start(_ coordinator: SwipeCoordinator) {
        self.coordinator = coordinator
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let coordinator else { return event }

        // Discrete mouse wheels carry neither phase nor momentum. They are
        // never a swipe, so let them scroll the list and leave swipe state be.
        if event.phase == [] && event.momentumPhase == [] { return event }

        // Start of a physical gesture. Reset, and lock onto the row under the
        // pointer right now so the rest of the gesture (including the action on
        // release) targets that one row even if the list reorders underneath.
        if event.phase == .began {
            // An interrupted prior gesture could leave its row shifted. Snap it
            // back before starting fresh.
            if let prev = lockedID, !settled { coordinator.close(id: prev) }
            accumX = 0
            accumY = 0
            axis = nil
            settled = false
            lockedID = coordinator.hoveredID
        }

        guard let id = lockedID else { return event } // not over a row: list scrolls

        // Accumulate physical travel only. Inertial momentum never votes on the
        // axis, or it could revive a settled horizontal swipe.
        if event.momentumPhase == [] {
            accumX += event.scrollingDeltaX // natural scrolling: swipe left -> negative
            accumY += event.scrollingDeltaY
        }

        // Decide the axis once a few points of travel make the intent clear, so
        // a tiny orthogonal jitter at the very start can't lock the wrong axis
        // and silently swallow an otherwise valid swipe.
        if axis == nil, abs(accumX) + abs(accumY) >= 4 {
            axis = abs(accumX) > abs(accumY) ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return event } // vertical/undecided -> list scrolls

        // Already settled this gesture: swallow trailing momentum so the list
        // does not scroll, but never re-drive the offset or fire again.
        if settled { return nil }

        coordinator.drag(id: id, translationX: accumX)

        // Settle once, on the physical release. A cancel just snaps back. Either
        // way `settled` makes the trailing momentum a no-op, so the action fires
        // at most once per gesture.
        if event.phase == .ended {
            let settle = { coordinator.end(id: id) }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                settle()
            } else {
                withAnimation(.snappy(duration: 0.22), settle)
            }
            settled = true
        } else if event.phase == .cancelled {
            withAnimation(.snappy(duration: 0.22)) { coordinator.close(id: id) }
            settled = true
        }
        return nil // consume horizontal so the list doesn't also scroll
    }
}
