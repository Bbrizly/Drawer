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
    /// Set by the facade: the Bureau drawer's on-screen frame while it is
    /// mounted, or nil when it is not visible. A sticky that settles with its
    /// center inside this frame is dropped back into the drawer.
    var drawerFrame: (() -> NSRect?)?

    private var panels: [UUID: StickyPanelHosting] = [:]
    private var models: [UUID: StickyModel] = [:]
    private var roster = StickyRoster()
    private var followToken: Any?
    private var windowMoveObserver: NSObjectProtocol?
    private var settleWork: [ObjectIdentifier: DispatchWorkItem] = [:]

    private lazy var hover: HoverScrollMover = {
        let mover = HoverScrollMover(
            tuning: tuning.document.hoverScroll,
            windowUnder: { [weak self] event in self?.stickyWindow(under: event) }
        )
        mover.onSettled = { [weak self] window in self?.stickySettled(window) }
        mover.clampOnScreen = { origin, size in StickyPanelManager.clampOnScreen(origin: origin, size: size) }
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
    func spawn(receiptID: UUID, title: String, at origin: CGPoint, size: StickySize = .full, growIn: Bool = false) -> StickyPanelHosting {
        if let existing = panels[receiptID] {
            let clamped = Self.clampOnScreen(origin: origin, size: existing.contentSize)
            existing.frameOrigin = clamped
            existing.present()
            roster.insert(receiptID, cap: cap) // move to newest
            persist(receiptID, state: .sticky, origin: clamped, size: models[receiptID]?.size ?? size)
            return existing
        }

        let model = StickyModel(receiptID: receiptID, title: title, size: size)
        model.subtasks = subtasksProvider?(receiptID) ?? []
        model.subtaskVisibleCap = max(1, tuning.document.sticky.subtaskVisibleCap)
        model.pullOutScale = tuning.document.sticky.pullOutScale
        model.growsIn = growIn
        model.onResize = { [weak self] newSize in self?.resize(receiptID, to: newSize) }
        model.onReturnHome = { [weak self] in self?.sendHome(receiptID) }
        model.onLayoutChanged = { [weak self] in self?.refit(receiptID) }
        model.onCommitTitle = { [weak self] newTitle in self?.onCommitTitle?(receiptID, newTitle) }
        model.onCommitSubtasks = { [weak self] lines in self?.onCommitSubtasks?(receiptID, lines) }

        let panelSize = StickyMetrics.size(for: model)
        let clamped = Self.clampOnScreen(origin: origin, size: panelSize)
        let host = makePanel(Spawn(
            receiptID: receiptID,
            model: model,
            origin: clamped,
            size: panelSize
        ))
        panels[receiptID] = host
        models[receiptID] = model
        host.present()
        persist(receiptID, state: .sticky, origin: clamped, size: size)

        hover.updateTuning(tuning.document.hoverScroll)
        hover.start()
        startWindowMoveObserver()

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
        if panels.isEmpty { hover.stop(); stopWindowMoveObserver() }
        onLiveCountChanged?(panels.count)
    }

    /// The pulled-out `.full` size at the live scale, used by the drag follow.
    private var pullOutFullSize: CGSize {
        StickyMetrics.size(.full, pullOutScale: CGFloat(tuning.document.sticky.pullOutScale))
    }

    /// The continuous drag handoff (spec flow c): spawn the sticky (grown from
    /// the drawer slip) centered under the cursor, then follow the cursor until
    /// mouseUp with a local monitor so the paper reads as one object crossing the
    /// drawer edge.
    func spawnFromDrag(receiptID: UUID, title: String, at origin: CGPoint) {
        let host = spawn(receiptID: receiptID, title: title, at: origin, size: .full, growIn: true)
        installFollow(host: host)
    }

    private func installFollow(host: StickyPanelHosting) {
        removeFollow()
        let size = pullOutFullSize
        followToken = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak host] event in
            guard let self, let host else { return event }
            let m = NSEvent.mouseLocation
            host.frameOrigin = Self.clampOnScreen(
                origin: CGPoint(x: m.x - size.width / 2, y: m.y - size.height / 2),
                size: size
            )
            if event.type == .leftMouseUp {
                // Same settle rule as every other movement path: drop home if it
                // landed over the drawer, else persist where it rests.
                if let window = host.hostWindow {
                    self.stickySettled(window)
                } else {
                    self.persist(host.receiptID, state: .sticky, origin: host.frameOrigin, size: .full)
                }
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
        if panels.isEmpty { hover.stop(); stopWindowMoveObserver() }
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
        stopWindowMoveObserver()
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

    // MARK: settle / drop back into the drawer

    /// Pure decision, testable without a window: a settled center inside the
    /// Bureau drawer's on-screen frame means the sticky goes home.
    func shouldReturnHome(center: CGPoint) -> Bool {
        guard let frame = drawerFrame?() else { return false }
        return frame.contains(center)
    }

    /// The one settle rule shared by every movement path (drag-follow mouseUp,
    /// hover-scroll rest, window-background drag): if the sticky came to rest
    /// over the drawer, send it home (which drops a sprite back into the pile);
    /// otherwise persist its new resting spot.
    private func stickySettled(_ window: NSWindow) {
        guard let (id, host) = panels.first(where: { $0.value.hostWindow === window }) else { return }
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if shouldReturnHome(center: center) {
            sendHome(id)
            return
        }
        let size = models[id]?.size ?? .full
        persist(id, state: .sticky, origin: host.frameOrigin, size: size)
    }

    /// Watches window-background drags of the sticky panels. A programmatic move
    /// (hover-scroll, drag-follow) also posts this, which is harmless: the settle
    /// is debounced and idempotent. Installed with the first sticky, torn down
    /// with the last.
    private func startWindowMoveObserver() {
        guard windowMoveObserver == nil else { return }
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow else { return }
                guard self.panels.values.contains(where: { $0.hostWindow === window }) else { return }
                self.scheduleWindowSettle(window)
            }
        }
    }

    private func stopWindowMoveObserver() {
        if let windowMoveObserver { NotificationCenter.default.removeObserver(windowMoveObserver) }
        windowMoveObserver = nil
        for work in settleWork.values { work.cancel() }
        settleWork.removeAll()
    }

    /// Debounces the settle to ~350ms after the last move so a drag that is
    /// still in flight does not keep firing.
    private func scheduleWindowSettle(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        settleWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.settleWork[ObjectIdentifier(window)] = nil
                // A paused drag is not a settle: with the button still held,
                // settling here would send the note home out from under the
                // hand. Wait another beat until the button is released.
                if NSEvent.pressedMouseButtons & 1 != 0 {
                    self.scheduleWindowSettle(window)
                    return
                }
                self.stickySettled(window)
            }
        }
        settleWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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

    // MARK: off-screen rescue

    /// The live screen work areas, so a clamp never parks a note under the menu
    /// bar or the dock.
    private static var screenFrames: [NSRect] { NSScreen.screens.map { $0.visibleFrame } }

    /// Clamps `origin` so at least `minVisible` points of a window of `size`
    /// stay on some screen, in both axes. A note that is already sufficiently
    /// visible is left exactly where it is; one that is off-screen is pulled back
    /// onto the nearest screen so it is never lost. Pure, so it is tested with a
    /// fixed screen list and no window server.
    static func clampOnScreen(origin: CGPoint, size: CGSize, minVisible: CGFloat = 40) -> CGPoint {
        clampOnScreen(origin: origin, size: size, screens: screenFrames, minVisible: minVisible)
    }

    static func clampOnScreen(origin: CGPoint, size: CGSize, screens: [NSRect], minVisible: CGFloat = 40) -> CGPoint {
        guard !screens.isEmpty else { return origin }
        let rect = CGRect(origin: origin, size: size)
        // A tiny window cannot show more of itself than it has.
        let needX = min(minVisible, size.width)
        let needY = min(minVisible, size.height)

        // Enough already visible on some screen (both axes)? Leave it put.
        func visible(_ s: NSRect) -> CGFloat {
            let ox = min(rect.maxX, s.maxX) - max(rect.minX, s.minX)
            let oy = min(rect.maxY, s.maxY) - max(rect.minY, s.minY)
            return min(ox, oy)
        }
        if screens.contains(where: { visible($0) >= min(needX, needY) }) { return origin }

        // Lost off-screen: bring it back onto the screen nearest its center.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = screens.min(by: {
            hypot($0.midX - center.x, $0.midY - center.y) < hypot($1.midX - center.x, $1.midY - center.y)
        })!
        var o = origin
        o.x = min(max(o.x, screen.minX + needX - size.width), screen.maxX - needX)
        o.y = min(max(o.y, screen.minY + needY - size.height), screen.maxY - needY)
        return o
    }
}
