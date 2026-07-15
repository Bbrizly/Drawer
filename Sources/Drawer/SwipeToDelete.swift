import AppKit
import Observation
import SwiftUI

/// Shared swipe state for the rows, keyed by task id. Both inputs (mouse
/// click-drag and two-finger trackpad swipe) write here, so they can never
/// fight over a private per-row offset. Only one row is open at a time.
@MainActor
@Observable
final class SwipeCoordinator {
    let deleteWidth: CGFloat = 72
    /// How far a row slides right to reveal the in-progress affordance. Past
    /// half of this on release, the row is marked in progress and snaps back.
    let progressWidth: CGFloat = 72

    private var offsets: [String: CGFloat] = [:]
    private(set) var openID: String?
    /// The row under the pointer. The scroll monitor swipes this one, so no
    /// hit-testing or coordinate conversion is needed.
    var hoveredID: String?
    /// Set once by the view. Called when a right swipe crosses the trigger
    /// threshold, with the row id, so the store can flip its in-progress flag.
    var onProgress: ((String) -> Void)?
    /// Set once by the view. Called when a left swipe on the task page (not over
    /// a row) crosses the threshold, to hide the whole drawer.
    var onCloseDrawer: (() -> Void)?
    /// Feature flags. When a direction is off, the row can't slide that way and
    /// its action never fires, so both inputs (mouse and trackpad) honor it.
    var deleteEnabled = true
    var progressEnabled = true
    /// True while the pointer is over swipe-navigable chrome (a header bar). The
    /// scroll monitor then reads a horizontal two-finger swipe there as a page
    /// switch between the task list and the idea board, not a row swipe.
    var pointerOverChrome = false
    // Page flag lives here (not @State) so the scroll monitor can flip it
    // without a captured binding going stale mid-gesture.
    var showingBoard = false
    /// True while the Bureau tray fills the drawer. A horizontal swipe there
    /// belongs to the Bureau, so it must never page to the idea board.
    var bureauModeActive = false
    /// True when the cursor sits over a floating Bureau sticky, so a two-finger
    /// pan moves the note (via HoverScrollMover) and never pages to the board.
    /// A closure so the drawer module stays free of any DrawerBureau type.
    var pointerOverSticky: () -> Bool = { false }
    /// The gesture belongs to the Bureau (its tray or a floating sticky), so the
    /// scroll monitor treats it as content, not a page swipe.
    var overBureauContent: Bool { bureauModeActive || pointerOverSticky() }
    /// How much of the screen the board covers: 0 = normal panel, 1 = full
    /// screen. A right swipe on the board raises it, a left swipe lowers it.
    var boardCoverage: CGFloat = 0
    /// The last coverage the user settled on (> 0), remembered across board
    /// close/open so the board comes back at the size it was left at.
    var lastBoardCoverage: CGFloat = 0

    /// Points of swipe to move coverage by 1 (normal -> full in one firm swipe).
    /// Settings-tunable; lower = a small swipe covers more.
    static var coverageSwipeScale: CGFloat {
        let v = UserDefaults.standard.double(forKey: "boardSwipeScale")
        return v > 0 ? CGFloat(v) : 300
    }

    /// Coverage for a live swipe: `start` (coverage when the swipe began) plus
    /// the swipe distance so far, clamped 0...1. Pure, testable without events.
    static func coverage(from start: CGFloat, dx: CGFloat) -> CGFloat {
        max(0, min(1, start + dx / coverageSwipeScale))
    }

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
    /// This gesture began over header chrome, so a decisive horizontal swipe
    /// pages between the task list and the board instead of swiping a row.
    private var pageMode = false
    /// Board coverage when the page swipe began, so the live update tracks the
    /// finger from where it started.
    private var coverageStart: CGFloat = 0

    /// Minimum physical horizontal travel (points) to commit a page switch.
    private static let pageSwipeThreshold: CGFloat = 50

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

        // Start of a physical gesture. Decide once what this swipe targets and
        // hold it for the whole gesture. Over header chrome it pages between the
        // task list and the board; otherwise it swipes the row under the pointer.
        if event.phase == .began {
            // An interrupted prior gesture could leave its row shifted. Snap it
            // back before starting fresh.
            if let prev = lockedID, !settled { coordinator.close(id: prev) }
            accumX = 0
            accumY = 0
            axis = nil
            settled = false
            coverageStart = coordinator.boardCoverage
            // Tasks page: any swipe that is not on a row pages forward to the
            // board, using the same hoveredID signal the row swipes rely on.
            // Board page: only the header (pointerOverChrome) pages back, so the
            // canvas keeps its own horizontal pan.
            if coordinator.overBureauContent {
                // Over the Bureau tray or a floating sticky: the gesture moves a
                // note, never pages. Fall through as plain content so the event
                // passes to the sticky mover and the board stays put.
                pageMode = false
                lockedID = nil
            } else if coordinator.showingBoard {
                pageMode = coordinator.pointerOverChrome
                lockedID = nil
            } else if coordinator.hoveredID == nil {
                pageMode = true
                lockedID = nil
            } else {
                pageMode = false
                lockedID = coordinator.hoveredID
            }
        }

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
        guard axis == .horizontal else { return event } // vertical/undecided -> scrolls

        // Already settled this gesture: swallow trailing momentum so nothing
        // else scrolls, but never re-drive the offset or fire again.
        if settled { return nil }

        // Page swipe over the header chrome. On the board the coverage tracks the
        // finger live; on the task list a decisive right swipe opens the board.
        if pageMode {
            if coordinator.showingBoard {
                coordinator.boardCoverage = SwipeCoordinator.coverage(from: coverageStart, dx: accumX)
                if event.phase == .ended {
                    // At minimum coverage and still pushing left -> back to tasks.
                    if coverageStart <= 0 && accumX <= -Self.pageSwipeThreshold {
                        coordinator.showingBoard = false
                        coordinator.boardCoverage = 0
                    } else if coordinator.boardCoverage > 0.05 {
                        // Remember where the swipe settled so a reopened board
                        // comes back at this size.
                        coordinator.lastBoardCoverage = coordinator.boardCoverage
                    }
                    settled = true
                } else if event.phase == .cancelled {
                    settled = true
                }
            } else if event.phase == .ended {
                // Right opens the board; left (right-to-left) closes the drawer.
                if accumX >= Self.pageSwipeThreshold {
                    coordinator.showingBoard = true
                } else if accumX <= -Self.pageSwipeThreshold {
                    coordinator.onCloseDrawer?()
                }
                settled = true
            } else if event.phase == .cancelled {
                settled = true
            }
            return nil // consume horizontal so the page/canvas underneath stays put
        }

        // Row swipe: drive the row under the pointer.
        guard let id = lockedID else { return event } // not over a row: list scrolls
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
