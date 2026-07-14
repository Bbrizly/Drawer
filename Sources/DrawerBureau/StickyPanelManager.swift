import AppKit

/// Owns every live sticky note: it spawns the panels, caps them at
/// `sticky.liveCap` (default 12, spec "Pull-out"), sends the oldest home when
/// the cap is exceeded, and persists each sticky's state, position, and size to
/// `ReceiptStore`. It also drives the drag handoff follow (flow c) and hosts the
/// `HoverScrollMover`.
///
/// The cap and retire ORDER live in a plain `StickyRoster` (tested without a
/// display); this type wires that decision to real panels, the store, and the
/// scene. Panel creation is injected (`makePanel`) so the state-transition tests
/// stand in a fake and never touch the window server.
@MainActor
final class StickyPanelManager {
    /// A sticky about to be built: everything the panel factory needs.
    struct Spawn {
        let receiptID: UUID
        let model: StickyModel
        let origin: CGPoint
        let size: CGSize
    }

    typealias PanelFactory = @MainActor (Spawn) -> StickyPanelHosting

    nonisolated static let realPanelFactory: PanelFactory = { spawn in
        StickyPanel(
            receiptID: spawn.receiptID,
            model: spawn.model,
            origin: spawn.origin,
            size: spawn.size
        )
    }

    private let receipts: ReceiptStore
    private let tuning: BureauTuning
    private let makePanel: PanelFactory

    /// Set by the facade: respawn a sprite in the drawer when a sticky goes home
    /// (either the return-home button or being retired as the oldest).
    var onReturnToDrawer: ((ReceiptLink) -> Void)?
    /// Set by the facade (R3): seed a fresh sticky's subtask lines, and write
    /// title / subtask edits back through `TodoStore`.
    var subtasksProvider: ((UUID) -> [String])?
    var onCommitTitle: ((UUID, String) -> Void)?
    var onCommitSubtasks: ((UUID, [String]) -> Void)?
    /// Set by the facade (R4): the number of live stickies changed, so the
    /// stamp watcher can start or stop.
    var onLiveCountChanged: ((Int) -> Void)?

    private var panels: [UUID: StickyPanelHosting] = [:]
    private var models: [UUID: StickyModel] = [:]
    private var roster = StickyRoster()
    private var followToken: Any?

    private lazy var hover: HoverScrollMover = {
        let mover = HoverScrollMover(
            tuning: tuning.document.hoverScroll,
            windowUnder: { [weak self] event in self?.stickyWindow(under: event) }
        )
        mover.onSettled = { [weak self] window in self?.persistPosition(of: window) }
        return mover
    }()

    init(
        receipts: ReceiptStore,
        tuning: BureauTuning,
        makePanel: @escaping PanelFactory = StickyPanelManager.realPanelFactory
    ) {
        self.receipts = receipts
        self.tuning = tuning
        self.makePanel = makePanel
    }

    private var cap: Int { max(1, tuning.document.sticky.liveCap) }

    var liveCount: Int { panels.count }
    func isLive(_ id: UUID) -> Bool { panels[id] != nil }

    /// Pushes hot-reloaded feel values into the live hover-scroll monitor. The
    /// cap is read per spawn, so only the mover needs a live refresh.
    func tuningChanged() { hover.updateTuning(tuning.document.hoverScroll) }

    // MARK: spawn

    /// Builds (or refronts) a sticky for `receiptID`, marks the receipt
    /// `.sticky` at `origin`/`size` in the store, and enforces the cap: if this
    /// pushes the live count past `liveCap`, the oldest sticky is sent home.
    @discardableResult
    func spawn(receiptID: UUID, title: String, at origin: CGPoint, size: StickySize = .full) -> StickyPanelHosting {
        if let existing = panels[receiptID] {
            existing.frameOrigin = origin
            existing.present()
            roster.insert(receiptID, cap: cap) // move to newest
            persist(receiptID, state: .sticky, origin: origin, size: models[receiptID]?.size ?? size)
            return existing
        }

        let model = StickyModel(receiptID: receiptID, title: title, size: size)
        model.subtasks = subtasksProvider?(receiptID) ?? []
        model.subtaskVisibleCap = max(1, tuning.document.sticky.subtaskVisibleCap)
        model.onResize = { [weak self] newSize in self?.resize(receiptID, to: newSize) }
        model.onReturnHome = { [weak self] in self?.sendHome(receiptID) }
        model.onLayoutChanged = { [weak self] in self?.refit(receiptID) }
        model.onCommitTitle = { [weak self] newTitle in self?.onCommitTitle?(receiptID, newTitle) }
        model.onCommitSubtasks = { [weak self] lines in self?.onCommitSubtasks?(receiptID, lines) }

        let host = makePanel(Spawn(
            receiptID: receiptID,
            model: model,
            origin: origin,
            size: StickyMetrics.size(for: model)
        ))
        panels[receiptID] = host
        models[receiptID] = model
        host.present()
        persist(receiptID, state: .sticky, origin: origin, size: size)

        hover.updateTuning(tuning.document.hoverScroll)
        hover.start()

        if let retired = roster.insert(receiptID, cap: cap), retired != receiptID {
            sendHome(retired)
        }
        onLiveCountChanged?(panels.count)
        return host
    }

    // MARK: stamp support (R4)

    /// The live sticky windows, for the stamp controller's zone check.
    func stickyFrames() -> [(id: UUID, frame: NSRect)] {
        panels.compactMap { id, host in host.hostWindow.map { (id, $0.frame) } }
    }

    func model(for id: UUID) -> StickyModel? { models[id] }

    /// Closes a sticky without changing its stored state or respawning a
    /// sprite; the DONE flow files the receipt itself and the tray takes over.
    func close(_ id: UUID) {
        roster.remove(id)
        if let host = panels.removeValue(forKey: id) { host.dismiss() }
        models[id] = nil
        if panels.isEmpty { hover.stop() }
        onLiveCountChanged?(panels.count)
    }

    /// The continuous drag handoff (spec flow c): spawn the sticky under the
    /// held cursor, then follow the cursor until mouseUp with a local monitor so
    /// the paper reads as one object crossing the drawer edge. `grab` is the
    /// cursor's offset from the slip center, kept constant so the note stays
    /// glued to the same spot under the pointer.
    func spawnFromDrag(receiptID: UUID, title: String, at origin: CGPoint, grab: CGPoint) {
        let host = spawn(receiptID: receiptID, title: title, at: origin, size: .full)
        installFollow(host: host, grab: grab)
    }

    private func installFollow(host: StickyPanelHosting, grab: CGPoint) {
        removeFollow()
        let size = StickyMetrics.size(.full)
        followToken = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak host] event in
            guard let self, let host else { return event }
            let m = NSEvent.mouseLocation
            host.frameOrigin = CGPoint(
                x: m.x - grab.x - size.width / 2,
                y: m.y - grab.y - size.height / 2
            )
            if event.type == .leftMouseUp {
                self.persist(host.receiptID, state: .sticky, origin: host.frameOrigin, size: .full)
                self.removeFollow()
            }
            return nil // this drag now belongs to the sticky, consume it
        }
    }

    private func removeFollow() {
        if let followToken { NSEvent.removeMonitor(followToken) }
        followToken = nil
    }

    // MARK: retire / return home

    /// Sends a sticky back into the drawer: mark the receipt `.inDrawer`, close
    /// its panel, and ask the scene (via `onReturnToDrawer`) to respawn a sprite.
    func sendHome(_ id: UUID) {
        roster.remove(id)
        if let host = panels.removeValue(forKey: id) { host.dismiss() }
        models[id] = nil
        if var link = receipts.document.receipts.first(where: { $0.id == id }) {
            link.state = .inDrawer
            receipts.update(link)
            onReturnToDrawer?(link)
        }
        if panels.isEmpty { hover.stop() }
        onLiveCountChanged?(panels.count)
    }

    /// Reopens the panels for receipts persisted as `.sticky` (a relaunch, or
    /// re-entering the drawer). Called when Bureau mode becomes visible so a
    /// sticky is never a receipt with no window and no sprite. Idempotent: it
    /// skips ids that are already live.
    func restore() {
        for link in receipts.document.receipts where link.state == .sticky && panels[link.id] == nil {
            spawn(
                receiptID: link.id,
                title: link.textSnapshot,
                at: CGPoint(x: link.position.x, y: link.position.y),
                size: link.stickySize
            )
        }
    }

    /// Closes every live sticky without changing its stored state, for teardown.
    func closeAll() {
        removeFollow()
        for host in panels.values { host.dismiss() }
        panels.removeAll()
        models.removeAll()
        roster = StickyRoster()
        hover.stop()
        onLiveCountChanged?(0)
    }

    // MARK: resize / persistence

    private func resize(_ id: UUID, to size: StickySize) {
        guard let host = panels[id] else { return }
        refit(id)
        persist(id, state: .sticky, origin: host.frameOrigin, size: size)
    }

    /// Refits the panel to what the model shows now (size cycle, subtask rows
    /// appearing, "+N more" expansion).
    private func refit(_ id: UUID) {
        guard let host = panels[id], let model = models[id] else { return }
        host.contentSize = StickyMetrics.size(for: model)
    }

    private func persist(_ id: UUID, state: ReceiptState, origin: CGPoint, size: StickySize) {
        guard var link = receipts.document.receipts.first(where: { $0.id == id }) else { return }
        link.state = state
        link.position = ReceiptPosition(x: Double(origin.x), y: Double(origin.y))
        link.stickySize = size
        receipts.update(link)
    }

    private func persistPosition(of window: NSWindow) {
        guard let (id, host) = panels.first(where: { $0.value.hostWindow === window }) else { return }
        let size = models[id]?.size ?? .full
        persist(id, state: .sticky, origin: host.frameOrigin, size: size)
    }

    // MARK: hover-scroll resolution

    /// The live sticky window a scroll event landed on, or `nil`. Prefers the
    /// event's own window (correct even when panels overlap other apps), and
    /// falls back to a frame hit-test at the cursor when the event carries no
    /// window.
    private func stickyWindow(under event: NSEvent) -> NSWindow? {
        if let w = event.window, panels.values.contains(where: { $0.hostWindow === w }) {
            return w
        }
        let p = NSEvent.mouseLocation
        for host in panels.values {
            if let w = host.hostWindow, w.frame.contains(p) { return w }
        }
        return nil
    }
}
