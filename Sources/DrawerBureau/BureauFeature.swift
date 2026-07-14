import AppKit
import DrawerCore
import SpriteKit
import SwiftUI

/// The single type the `Drawer` target sees. Everything else in `DrawerBureau`
/// stays internal so the guard surface at every call site is exactly one import
/// and one type: drop the target from `Package.swift` and `canImport` goes
/// false, taking every Bureau branch with it and leaving today's app.
///
/// It owns the durable state (`ReceiptStore`), the hot-reloaded feel values
/// (`BureauTuning`), and the texture cache, and it exposes just what the drawer
/// needs: build the view, queue a task, read the queued count, and learn when
/// the panel hides so the scene can pause.
@MainActor
public final class BureauFeature: ObservableObject {
    /// Drives the queue-counter chip in the top strip.
    @Published public private(set) var queuedCount = 0
    /// Mirrors `PanelController.onVisibilityChange` so `BureauView` can pause
    /// the scene and view when the drawer is hidden (perf contract, spec risk 3).
    @Published public var panelVisible = true

    private let store: TodoStore
    let receipts: ReceiptStore
    let tuning: BureauTuning
    let textures = TextureRenderer()
    /// The one scene instance, owned here so it (and the receipts already in
    /// the drawer) survive the SwiftUI view mounting and unmounting as the mode
    /// is entered and left.
    let scene = BureauScene(size: CGSize(width: 300, height: 400))
    /// The live sticky notes (spec "Pull-out"). Owned here, not by `BureauView`,
    /// because a sticky floats on independently of whether the drawer is the
    /// visible bottom region.
    let stickies: StickyPanelManager
    /// The drawer slip size, shared so the drag handoff spawns a sticky that
    /// matches the sprite exactly (single source: `StickyMetrics.fullSlip`).
    let slipSize = StickyMetrics.fullSlip

    private var scale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    public init(store: TodoStore, directory: URL) {
        self.store = store
        let receipts = ReceiptStore(directory: directory)
        self.receipts = receipts
        self.tuning = BureauTuning(directory: directory)
        self.stickies = StickyPanelManager(receipts: receipts, tuning: tuning)
        tuning.startWatching()
        refreshQueue()

        // Wire the scene seams left for R2 (handoff + layout save) and the
        // sticky return path, all through the facade so the one owner holds the
        // scene, the store, the textures, and the panels.
        stickies.onReturnToDrawer = { [weak self] link in self?.spawnSprite(for: link) }
        scene.onSpriteDraggedPastBounds = { [weak self] sprite, cursor in
            self?.handleDragHandoff(sprite, cursorInScene: cursor)
        }
        scene.onReceiptsSettled = { [weak self] layout in self?.persistDrawerLayout(layout) }
    }

    // MARK: sticky pull-out (spec flow c)

    /// The drag left the drawer: despawn the sprite and hand the same paper to a
    /// floating sticky under the held cursor. `grab` is recovered from the sprite
    /// (its center was just set to `cursor - grab`), so the note keeps the exact
    /// grab point under the pointer and the seam reads as one object.
    private func handleDragHandoff(_ sprite: ReceiptSprite, cursorInScene cursor: CGPoint) {
        let id = sprite.receiptID
        let grab = CGPoint(x: cursor.x - sprite.position.x, y: cursor.y - sprite.position.y)
        let title = receipts.document.receipts.first(where: { $0.id == id })?.textSnapshot ?? ""
        sprite.removeFromParent()
        // Scene space and screen space are both y-up and, with resizeFill, one
        // scene unit is one point, so `grab` maps straight across.
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(
            x: mouse.x - grab.x - slipSize.width / 2,
            y: mouse.y - grab.y - slipSize.height / 2
        )
        stickies.spawnFromDrag(receiptID: id, title: title, at: origin, grab: grab)
    }

    /// Rebuilds a drawer sprite for a receipt coming home from a sticky and
    /// drops it back into the pile.
    private func spawnSprite(for link: ReceiptLink) {
        let texture = textures.texture(title: link.textSnapshot, size: slipSize, scale: scale)
        let sprite = ReceiptSprite(receiptID: link.id, texture: texture, size: slipSize)
        scene.dropIn(sprite)
    }

    /// Saves the settled drawer layout back to the store (R2 deliverable 6), one
    /// batched write per rest.
    private func persistDrawerLayout(_ layout: [UUID: (CGPoint, CGFloat)]) {
        var changes: [UUID: (ReceiptPosition, Double)] = [:]
        for (id, value) in layout {
            changes[id] = (ReceiptPosition(x: Double(value.0.x), y: Double(value.0.y)), Double(value.1))
        }
        receipts.updatePositions(changes)
    }

    // MARK: transition (read by DrawerView to build the push animation)

    public var transitionTuning: BureauTransitionTuning { tuning.document.transition }

    // MARK: panel visibility

    public func setPanelVisible(_ visible: Bool) { panelVisible = visible }

    // MARK: queue actions (spec flow a)

    /// Marks a task queued for the Bureau (right-click "Queue for Bureau").
    /// Idempotent: a task already queued or already in the drawer is left alone.
    public func queue(_ item: TodoItem) {
        guard !receipts.document.receipts.contains(where: { matches($0, item) }) else { return }
        receipts.add(ReceiptLink(
            textSnapshot: item.title,
            sectionDate: item.sectionDate,
            occurrence: item.occurrence,
            state: .queued
        ))
        refreshQueue()
    }

    /// Removes a task from the Bureau queue ("Remove from Bureau"). Only touches
    /// a still-queued receipt; one already printed into the drawer stays.
    public func unqueue(_ item: TodoItem) {
        for link in receipts.document.receipts where matches(link, item) && link.state == .queued {
            receipts.remove(link.id)
        }
        refreshQueue()
    }

    public func isQueued(_ item: TodoItem) -> Bool {
        receipts.document.receipts.contains { matches($0, item) && $0.state == .queued }
    }

    /// Recomputes the counter chip from the store. Called after any queue-state
    /// mutation, including `BureauView` printing queued receipts on mount.
    func refreshQueue() {
        queuedCount = receipts.document.receipts.filter { $0.state == .queued }.count
    }

    private func matches(_ link: ReceiptLink, _ item: TodoItem) -> Bool {
        link.sectionDate == item.sectionDate
            && link.occurrence == item.occurrence
            && link.textSnapshot == item.title
    }

    // MARK: view factory

    /// Builds the drawer view. `isActive` is true while Bureau mode is the
    /// visible bottom region; `BureauView` folds it together with
    /// `panelVisible` to decide when to pause.
    public func makeView(isActive: Bool) -> AnyView {
        AnyView(
            BureauView(
                scene: scene,
                receipts: receipts,
                tuning: tuning,
                store: store,
                feature: self,
                textures: textures,
                isActive: isActive
            )
        )
    }
}
