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
    /// Procedural noises (R4): chatter, ding, thunk, rustle.
    let sounds = BureauSounds()
    /// The stamp rack (R4): the right-edge tab, the two stamp heads, and the
    /// press consequences.
    let stamps = StampController()
    /// The screen-level shredder overlay: the bottom-right slot that shreds a
    /// pulled-out sticky dropped on it, same as the in-drawer shredder.
    let shredder = ShredderController()
    /// The portrait drawer slip size, shared by the sprites and the printer.
    /// Computed from tuning (`sticky.slipWidth`/`slipHeight`) so a slider edit
    /// resizes every slip. The pulled-out sticky is bigger by `pullOutScale`.
    var slipSize: CGSize {
        CGSize(width: tuning.document.sticky.slipWidth, height: tuning.document.sticky.slipHeight)
    }

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
        stickies.onReturnToDrawer = { [weak self] link, point in self?.spawnSprite(for: link, screenPoint: point) }
        stickies.subtasksProvider = { [weak self] id in self?.subtasks(for: id) ?? [] }
        stickies.onCommitTitle = { [weak self] id, title in self?.renameSticky(id, to: title) }
        stickies.onCommitSubtasks = { [weak self] id, lines in self?.setSubtasks(id, lines) }
        scene.onSpriteDraggedPastBounds = { [weak self] sprite, cursor in
            self?.handleDragHandoff(sprite, cursorInScene: cursor)
        }
        scene.onReceiptsSettled = { [weak self] layout in self?.persistDrawerLayout(layout) }
        scene.onShred = { [weak self] id in self?.shredReceipt(id) }

        // The drawer's on-screen frame while Bureau mode is mounted, so a sticky
        // dropped over the drawer goes home. `scene.view` is the live SKView; it
        // is nil (and its window hidden) when the drawer is off screen, which
        // naturally turns drop-back off then.
        stickies.drawerFrame = { [weak self] in
            guard let view = self?.scene.view, let window = view.window, window.isVisible else { return nil }
            return window.convertToScreen(view.convert(view.bounds, to: nil))
        }

        // R4: the stamp ritual and the drawer's noises.
        scene.onRustle = { [weak self] intensity in
            guard let self else { return }
            sounds.rustle(intensity, tuning: tuning.document.rustle)
        }
        stickies.onLiveCountChanged = { [weak self] count in
            self?.stamps.setWatching(count > 0)
            self?.shredder.setWatching(count > 0)
        }
        shredder.tuningProvider = { [weak self] in
            self?.tuning.document.shredder ?? BureauTuningDocument.defaults.shredder
        }
        stickies.onStickyMoved = { [weak self] frame in self?.shredder.stickyMoved(frame) }
        stickies.shredderOverlap = { [weak self] frame in self?.shredder.overlaps(frame) ?? false }
        stickies.onShredSticky = { [weak self] id, host in
            guard let self else { return }
            // Delete just the receipt (never the task) and run the slot animation
            // on the note's own window before it closes.
            self.shredReceipt(id)
            self.shredder.shred(host)
        }
        stamps.stickyFrames = { [weak self] in self?.stickies.stickyFrames() ?? [] }
        stamps.tuningProvider = { [weak self] in
            self?.tuning.document.stamp ?? BureauTuningDocument.defaults.stamp
        }
        stamps.onSlam = { [weak self] id, kind in self?.slam(id, kind) }
        stamps.onStamp = { [weak self] id, kind in self?.applyStamp(id, kind) }
        stamps.onPressMiss = { [weak self] in
            // The head pressed onto nothing: a soft thunk, no consequence.
            guard let self else { return }
            sounds.thunk(volume: tuning.document.stamp.thunkVolume * 0.5)
        }
    }

    // MARK: the stamp (R4, spec flow d)

    /// The slam moment: ink lands on the sticky a few degrees rotated with a
    /// double-strike ghost, the thunk plays, the haptic taps.
    private func slam(_ id: UUID, _ kind: StampKind) {
        let stamp = tuning.document.stamp
        stickies.model(for: id)?.stamp = StickyModel.AppliedStamp(
            kind: kind,
            rotationDeg: Double.random(in: stamp.inkRotationMinDeg...max(stamp.inkRotationMinDeg, stamp.inkRotationMaxDeg))
                * (Bool.random() ? 1 : -1),
            ghostOffsetPx: stamp.doubleStrikeOffsetPx
        )
        sounds.thunk(volume: stamp.thunkVolume)
        if stamp.hapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// The consequence once the arm retracts. DONE: check the task in
    /// Drawer.md, file the receipt (lifetime counter bumps), crumple the slip
    /// into the FILED tray. POSTPONED: pure return to the pile, the task
    /// untouched (spec: exact postpone semantics deferred by design).
    func applyStamp(_ id: UUID, _ kind: StampKind) {
        switch kind {
        case .done:
            if let item = liveItem(for: id), !item.isDone {
                store.toggle(item)
            }
            guard let link = receipts.document.receipts.first(where: { $0.id == id }) else { return }
            stickies.close(id)
            receipts.file(id)
            let texture = textures.texture(title: link.textSnapshot, size: slipSize, scale: scale)
            scene.fileIntoTray(ReceiptSprite(receiptID: id, texture: texture, size: slipSize))
            scene.setFiledCount(receipts.document.lifetimeFiled)
        case .postponed:
            stickies.sendHome(id)
        }
    }

    // MARK: sticky pull-out (spec flow c)

    /// The drag left the drawer: despawn the sprite and hand the same paper to a
    /// floating sticky. The pull-out is bigger than the drawer slip, so it can no
    /// longer keep the exact grab point under the pointer; instead it swells up
    /// centered under the cursor (the grow-in sells the size change).
    private func handleDragHandoff(_ sprite: ReceiptSprite, cursorInScene cursor: CGPoint) {
        let id = sprite.receiptID
        let title = receipts.document.receipts.first(where: { $0.id == id })?.textSnapshot ?? ""
        sprite.removeFromParent()
        let full = StickyMetrics.size(
            .full, pullOutScale: CGFloat(tuning.document.sticky.pullOutScale), slip: slipSize
        )
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - full.width / 2, y: mouse.y - full.height / 2)
        stickies.spawnFromDrag(receiptID: id, title: title, at: origin)
    }

    /// A slip fed into the shredder. Deletes only the receipt
    /// (bureau-receipts.json); the task in Drawer.md is never touched. Plays the
    /// shred sound as the tear-down animation runs in the scene.
    private func shredReceipt(_ id: UUID) {
        sounds.shred(volume: tuning.document.shredder.volume)
        receipts.remove(id)
    }

    /// Rebuilds a sprite for a receipt coming home from a sticky. A filed slip
    /// flies back to the FILED tray; any other slip is laid gently back on the
    /// drawer floor where the note was dropped (or the default spot when there
    /// is no drop location).
    private func spawnSprite(for link: ReceiptLink, screenPoint: CGPoint?) {
        let texture = textures.texture(
            title: link.textSnapshot, size: slipSize, scale: scale, age: link.ageFactor()
        )
        let sprite = ReceiptSprite(receiptID: link.id, texture: texture, size: slipSize)
        if link.state == .filed {
            scene.fileIntoTray(sprite, animated: true, crumple: false)
            return
        }
        scene.returnToDrawer(sprite, at: screenPoint.flatMap(sceneCoordinate))
    }

    /// Converts a screen point into the drawer scene's coordinate space (screen
    /// -> window -> view -> scene). Nil when the drawer is not on screen.
    private func sceneCoordinate(_ screen: CGPoint) -> CGPoint? {
        guard let view = scene.view, let window = view.window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: screen)
        let viewPoint = view.convert(windowPoint, from: nil)
        return scene.convertPoint(fromView: viewPoint)
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

    // MARK: sticky writeback (R3, spec flow e)

    /// The live task a receipt points at: the exact section/occurrence/title
    /// triple first, else a fuzzy re-link (which refreshes the snapshot on a
    /// match and expires the receipt on a miss). All edits resolve through
    /// here so a receipt never writes to a task it no longer represents.
    func liveItem(for receiptID: UUID) -> TodoItem? {
        guard var link = receipts.document.receipts.first(where: { $0.id == receiptID }) else { return nil }
        let candidates = store.todayItems + store.carriedItems + store.upcomingItems + store.backlogItems
        if let exact = candidates.first(where: { matches(link, $0) }) { return exact }
        let item = link.relink(against: candidates)
        receipts.update(link)
        return item
    }

    /// Sticky title edit: writes through `TodoStore.rename` (content-CAS, no
    /// watcher loop) and refreshes the receipt snapshot so the slip texture
    /// and future re-links follow the new title.
    func renameSticky(_ receiptID: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let item = liveItem(for: receiptID) else { return }
        store.rename(item, to: trimmed)
        guard var link = receipts.document.receipts.first(where: { $0.id == receiptID }) else { return }
        link.textSnapshot = trimmed
        receipts.update(link)
    }

    /// Subtasks are the task's indented note lines (spec "Pull-out"), not a
    /// modeled array; reading splits, writing joins through `TodoStore.setNote`.
    func subtasks(for receiptID: UUID) -> [String] {
        guard let note = liveItem(for: receiptID)?.note, !note.isEmpty else { return [] }
        return note.components(separatedBy: "\n")
    }

    func setSubtasks(_ receiptID: UUID, _ lines: [String]) {
        guard let item = liveItem(for: receiptID) else { return }
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.setNote(item, cleaned.joined(separator: "\n"))
    }

    // MARK: transition (read by DrawerView to build the push animation)

    public var transitionTuning: BureauTransitionTuning { tuning.document.transition }

    // MARK: panel visibility

    public func setPanelVisible(_ visible: Bool) { panelVisible = visible }

    // MARK: tuning panel (R5)

    private let tuningPanel = BureauTuningPanel()

    /// Long-press on the mode button (spec "Tuning system"): the hidden
    /// slider panel, bound live to bureau-tuning.json.
    public func toggleTuningPanel() { tuningPanel.toggle(tuning: tuning) }

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
