import AppKit
import DrawerCore
import XCTest
@testable import DrawerBureau

/// Drives `StickyPanelManager` against a `ReceiptStore` in a temp dir with a
/// FAKE panel (injected `makePanel`), so the state transitions and cap-retire
/// wiring are tested with no window server. The cap ORDER itself is proven in
/// `StickyRosterTests`; this checks the manager acts on it: closes the panel,
/// marks the store, and sends the receipt home.
@MainActor
final class StickyPanelManagerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A display-free stand-in for `StickyPanel`.
    private final class FakePanel: StickyPanelHosting {
        let receiptID: UUID
        var frameOrigin: CGPoint
        var contentSize: CGSize
        var hostWindow: NSWindow? { nil }
        private(set) var presented = false
        private(set) var dismissed = false

        init(receiptID: UUID, origin: CGPoint, size: CGSize) {
            self.receiptID = receiptID
            frameOrigin = origin
            contentSize = size
        }

        func present() { presented = true }
        func dismiss() { dismissed = true }
    }

    /// Writes a tuning file with the given live cap, then builds a manager whose
    /// panels are fakes we can inspect.
    private func makeManager(cap: Int) throws -> (StickyPanelManager, ReceiptStore, () -> [UUID: FakePanel]) {
        var doc = BureauTuningDocument.defaults
        doc.sticky.liveCap = cap
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(doc).write(to: dir.appendingPathComponent("bureau-tuning.json"))

        let receipts = ReceiptStore(directory: dir)
        let tuning = BureauTuning(directory: dir)
        var fakes: [UUID: FakePanel] = [:]
        let manager = StickyPanelManager(receipts: receipts, tuning: tuning) { spawn in
            let fake = FakePanel(receiptID: spawn.receiptID, origin: spawn.origin, size: spawn.size)
            fakes[spawn.receiptID] = fake
            return fake
        }
        return (manager, receipts, { fakes })
    }

    private func addLink(_ store: ReceiptStore, _ title: String) -> UUID {
        let link = ReceiptLink(textSnapshot: title, sectionDate: "2026-07-13", state: .inDrawer)
        store.add(link)
        return link.id
    }

    private func state(_ store: ReceiptStore, _ id: UUID) -> ReceiptState? {
        store.document.receipts.first { $0.id == id }?.state
    }

    func testSpawnMarksReceiptStickyWithPositionAndSize() throws {
        let (manager, store, _) = try makeManager(cap: 12)
        let id = addLink(store, "Call the landlord")
        manager.spawn(receiptID: id, title: "Call the landlord", at: CGPoint(x: 120, y: 240), size: .full)

        let saved = store.document.receipts.first { $0.id == id }
        XCTAssertEqual(saved?.state, .sticky)
        XCTAssertEqual(saved?.position.x, 120)
        XCTAssertEqual(saved?.position.y, 240)
        XCTAssertEqual(saved?.stickySize, .full)
        XCTAssertEqual(manager.liveCount, 1)
        XCTAssertTrue(manager.isLive(id))
    }

    func testSendHomeMarksInDrawerClosesPanelAndRespawns() throws {
        let (manager, store, fakes) = try makeManager(cap: 12)
        var returned: [UUID] = []
        manager.onReturnToDrawer = { link, _ in returned.append(link.id) }

        let id = addLink(store, "Ship the release")
        manager.spawn(receiptID: id, title: "Ship the release", at: .zero, size: .full)
        manager.sendHome(id)

        XCTAssertEqual(state(store, id), .inDrawer)
        XCTAssertEqual(returned, [id])
        XCTAssertTrue(fakes()[id]?.dismissed ?? false)
        XCTAssertEqual(manager.liveCount, 0)
        XCTAssertFalse(manager.isLive(id))
    }

    func testSpawnPastCapSendsOldestHome() throws {
        let (manager, store, fakes) = try makeManager(cap: 2)
        var returned: [UUID] = []
        manager.onReturnToDrawer = { link, _ in returned.append(link.id) }

        let a = addLink(store, "a")
        let b = addLink(store, "b")
        let c = addLink(store, "c")
        manager.spawn(receiptID: a, title: "a", at: .zero)
        manager.spawn(receiptID: b, title: "b", at: .zero)
        manager.spawn(receiptID: c, title: "c", at: .zero) // #3 over a cap of 2

        XCTAssertEqual(returned, [a])
        XCTAssertEqual(state(store, a), .inDrawer)
        XCTAssertEqual(state(store, b), .sticky)
        XCTAssertEqual(state(store, c), .sticky)
        XCTAssertEqual(manager.liveCount, 2)
        XCTAssertTrue(fakes()[a]?.dismissed ?? false)
    }

    /// Re-spawning an already-live sticky refronts it and moves it, without
    /// opening a second panel or bumping the live count.
    func testSpawnSameReceiptTwiceRefrontsInPlace() throws {
        let (manager, store, _) = try makeManager(cap: 12)
        let id = addLink(store, "a")
        manager.spawn(receiptID: id, title: "a", at: CGPoint(x: 10, y: 10))
        manager.spawn(receiptID: id, title: "a", at: CGPoint(x: 50, y: 60))
        XCTAssertEqual(manager.liveCount, 1)
        XCTAssertEqual(store.document.receipts.first { $0.id == id }?.position.x, 50)
    }

    /// A settle whose center lands inside the drawer frame sends the sticky
    /// home; anywhere else does not. Tested through the pure decision function
    /// so no real window is needed (the fakes have no host window).
    func testSettleInsideDrawerFrameReturnsHome() throws {
        let (manager, _, _) = try makeManager(cap: 12)
        manager.drawerFrame = { NSRect(x: 0, y: 0, width: 300, height: 400) }
        XCTAssertTrue(manager.shouldReturnHome(center: CGPoint(x: 150, y: 200)))
        XCTAssertFalse(manager.shouldReturnHome(center: CGPoint(x: 500, y: 500)))
        // No drawer on screen: nothing drops back.
        manager.drawerFrame = nil
        XCTAssertFalse(manager.shouldReturnHome(center: CGPoint(x: 150, y: 200)))
    }

    /// A window proposed fully off-screen is pulled back so at least 40pt shows
    /// on both axes; one already on-screen is left exactly where it is.
    func testClampOnScreenRescuesAnOffscreenWindow() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 200, height: 140)

        let clamped = StickyPanelManager.clampOnScreen(
            origin: CGPoint(x: 5000, y: -3000), size: size, screens: [screen], minVisible: 40
        )
        let rect = CGRect(origin: clamped, size: size)
        let visibleX = min(rect.maxX, screen.maxX) - max(rect.minX, screen.minX)
        let visibleY = min(rect.maxY, screen.maxY) - max(rect.minY, screen.minY)
        XCTAssertGreaterThanOrEqual(visibleX, 40)
        XCTAssertGreaterThanOrEqual(visibleY, 40)

        let onScreen = CGPoint(x: 300, y: 300)
        XCTAssertEqual(
            StickyPanelManager.clampOnScreen(origin: onScreen, size: size, screens: [screen], minVisible: 40),
            onScreen
        )
    }

    /// Restoring reopens exactly the receipts persisted as sticky, once each.
    func testRestoreReopensStickyReceipts() throws {
        let (manager, store, fakes) = try makeManager(cap: 12)
        store.add(ReceiptLink(textSnapshot: "kept", sectionDate: "2026-07-13", state: .sticky,
                              position: ReceiptPosition(x: 30, y: 40), stickySize: .title))
        store.add(ReceiptLink(textSnapshot: "in drawer", sectionDate: "2026-07-13", state: .inDrawer))

        manager.restore()
        XCTAssertEqual(manager.liveCount, 1)
        XCTAssertEqual(fakes().count, 1)
        // Idempotent: a second restore opens nothing new.
        manager.restore()
        XCTAssertEqual(manager.liveCount, 1)
    }

    /// A filed slip pulled out and sent home stays filed (so the facade files
    /// it back into the tray instead of the pile), unlike a normal slip which
    /// becomes in-drawer.
    func testSendHomeKeepsFiledSlipFiled() throws {
        let (manager, store, fakes) = try makeManager(cap: 12)
        var returnedStates: [ReceiptState] = []
        manager.onReturnToDrawer = { link, _ in returnedStates.append(link.state) }

        let link = ReceiptLink(textSnapshot: "done thing", sectionDate: "2026-07-13", state: .filed)
        store.add(link)
        manager.spawn(receiptID: link.id, title: "done thing", at: .zero, size: .full)
        // Pulling a filed slip out does not lose its filed state.
        XCTAssertEqual(state(store, link.id), .filed)

        manager.sendHome(link.id)
        XCTAssertEqual(state(store, link.id), .filed)
        XCTAssertEqual(returnedStates, [.filed])
        XCTAssertTrue(fakes()[link.id]?.dismissed ?? false)
    }
}

/// `StickyModel` is the R3 seam; its size cycle is pure and display-free.
@MainActor
final class StickyModelTests: XCTestCase {
    func testCycleSizeAdvancesAndNotifies() {
        let model = StickyModel(receiptID: UUID(), title: "x", size: .full)
        var reported: [StickySize] = []
        model.onResize = { reported.append($0) }

        model.cycleSize()
        XCTAssertEqual(model.size, .title)
        model.cycleSize()
        XCTAssertEqual(model.size, .chip)
        model.cycleSize()
        XCTAssertEqual(model.size, .full)
        XCTAssertEqual(reported, [.title, .chip, .full])
    }
}
