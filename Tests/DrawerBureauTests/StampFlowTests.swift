import DrawerCore
import XCTest
@testable import DrawerBureau

/// The stamp consequences (R4, spec flow d), driven through the facade with a
/// real file in a temp dir. The arm animation and windows are display-side;
/// what must hold is: DONE checks the task in Drawer.md and files the receipt
/// (lifetime counter bumps), POSTPONED returns it to the pile untouched.
@MainActor
final class StampFlowTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("Drawer.md")
        try "## 2026-07-13\n- [ ] Ship the release\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFeature() -> (BureauFeature, TodoStore) {
        let store = TodoStore(fileURL: fileURL, todayProvider: { "2026-07-13" })
        store.reload()
        return (BureauFeature(store: store, directory: dir), store)
    }

    private func stickyReceipt(_ feature: BureauFeature, _ store: TodoStore) -> UUID {
        feature.queue(store.todayItems[0])
        var link = feature.receipts.document.receipts[0]
        link.state = .sticky
        feature.receipts.update(link)
        return link.id
    }

    func testDoneChecksTheTaskAndFilesTheReceipt() throws {
        let (feature, store) = makeFeature()
        let id = stickyReceipt(feature, store)
        feature.applyStamp(id, .done)
        XCTAssertTrue(try String(contentsOf: fileURL, encoding: .utf8).contains("- [x] Ship the release"))
        XCTAssertEqual(feature.receipts.document.receipts.first { $0.id == id }?.state, .filed)
        XCTAssertEqual(feature.receipts.document.lifetimeFiled, 1)
    }

    func testPostponedReturnsTheReceiptAndLeavesTheFile() throws {
        let (feature, store) = makeFeature()
        let id = stickyReceipt(feature, store)
        feature.applyStamp(id, .postponed)
        XCTAssertTrue(try String(contentsOf: fileURL, encoding: .utf8).contains("- [ ] Ship the release"))
        XCTAssertEqual(feature.receipts.document.receipts.first { $0.id == id }?.state, .inDrawer)
        XCTAssertEqual(feature.receipts.document.lifetimeFiled, 0)
    }

    func testDoneOnAlreadyCheckedTaskDoesNotUncheckIt() throws {
        let (feature, store) = makeFeature()
        let id = stickyReceipt(feature, store)
        store.toggle(store.todayItems[0]) // checked externally first
        feature.applyStamp(id, .done)
        XCTAssertTrue(try String(contentsOf: fileURL, encoding: .utf8).contains("- [x] Ship the release"))
        XCTAssertEqual(feature.receipts.document.receipts.first { $0.id == id }?.state, .filed)
    }
}

/// The Monday ceremony's week logic (spec Decision 4), pure and clock-free.
@MainActor
final class TrayClearTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    // The week rolls at local midnight Monday, so the fixtures sit mid-week,
    // far enough from any boundary to read the same in every timezone.

    func testSameISOWeekIsNotNew() {
        // Tuesday to Friday of the week starting Monday 2026-07-13.
        XCTAssertFalse(ReceiptStore.isNewISOWeek(
            since: date("2026-07-14T12:00:00Z"),
            now: date("2026-07-17T12:00:00Z")
        ))
    }

    func testNextWeekIsNew() {
        // Friday to the following Tuesday, crossing Monday 2026-07-20.
        XCTAssertTrue(ReceiptStore.isNewISOWeek(
            since: date("2026-07-17T12:00:00Z"),
            now: date("2026-07-21T12:00:00Z")
        ))
    }

    func testEarlierDateIsNeverNew() {
        XCTAssertFalse(ReceiptStore.isNewISOWeek(
            since: date("2026-07-20T09:00:00Z"),
            now: date("2026-07-13T09:00:00Z")
        ))
    }

    func testFirstCheckStampsTheClockWithoutClearing() {
        let store = ReceiptStore(directory: dir)
        store.add(ReceiptLink(textSnapshot: "kept", sectionDate: "2026-07-13", state: .filed))
        XCTAssertFalse(store.clearTrayIfNewWeek(now: date("2026-07-13T09:00:00Z")))
        XCTAssertEqual(store.document.receipts.count, 1)
        XCTAssertNotNil(store.document.trayClearedAt)
    }

    func testNewWeekClearsFiledOnlyAndKeepsLifetime() {
        let store = ReceiptStore(directory: dir)
        store.add(ReceiptLink(textSnapshot: "filed", sectionDate: "2026-07-13", state: .filed))
        store.add(ReceiptLink(textSnapshot: "in drawer", sectionDate: "2026-07-13", state: .inDrawer))
        store.file(store.document.receipts[0].id) // lifetime -> 1
        XCTAssertFalse(store.clearTrayIfNewWeek(now: date("2026-07-16T09:00:00Z")))
        XCTAssertTrue(store.clearTrayIfNewWeek(now: date("2026-07-20T09:00:00Z")))
        XCTAssertEqual(store.document.receipts.map(\.state), [.inDrawer])
        XCTAssertEqual(store.document.lifetimeFiled, 1)
    }
}
