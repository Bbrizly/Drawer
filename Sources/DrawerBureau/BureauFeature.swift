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

    public init(store: TodoStore, directory: URL) {
        self.store = store
        self.receipts = ReceiptStore(directory: directory)
        self.tuning = BureauTuning(directory: directory)
        tuning.startWatching()
        refreshQueue()
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
