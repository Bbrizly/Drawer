import DrawerCore
import XCTest
@testable import DrawerBureau

@MainActor
final class BureauFeatureTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("Drawer.md")
        try "## 2026-07-13\n- [ ] Call the landlord\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFeature() -> BureauFeature {
        let store = TodoStore(fileURL: fileURL, todayProvider: { "2026-07-13" })
        return BureauFeature(store: store, directory: dir)
    }

    private func sampleItem() -> TodoItem {
        TodoItem(
            rawLine: "- [ ] Call the landlord",
            title: "Call the landlord",
            isDone: false,
            minutes: 25,
            sectionDate: "2026-07-13"
        )
    }

    func testQueueBumpsCountAndMarksQueued() {
        let feature = makeFeature()
        let item = sampleItem()
        XCTAssertFalse(feature.isQueued(item))
        feature.queue(item)
        XCTAssertTrue(feature.isQueued(item))
        XCTAssertEqual(feature.queuedCount, 1)
    }

    func testQueueIsIdempotent() {
        let feature = makeFeature()
        let item = sampleItem()
        feature.queue(item)
        feature.queue(item)
        XCTAssertEqual(feature.queuedCount, 1)
    }

    func testUnqueueRemovesTheReceipt() {
        let feature = makeFeature()
        let item = sampleItem()
        feature.queue(item)
        feature.unqueue(item)
        XCTAssertFalse(feature.isQueued(item))
        XCTAssertEqual(feature.queuedCount, 0)
    }

    /// A queued task lands in `bureau-receipts.json`, so a relaunch (a fresh
    /// store over the same directory) still shows it queued.
    func testQueuedReceiptPersistsToDisk() {
        let feature = makeFeature()
        feature.queue(sampleItem())
        let reloaded = ReceiptStore(directory: dir)
        XCTAssertEqual(reloaded.document.receipts.filter { $0.state == .queued }.count, 1)
    }

    func testPanelVisibilityFlagFlows() {
        let feature = makeFeature()
        XCTAssertTrue(feature.panelVisible)
        feature.setPanelVisible(false)
        XCTAssertFalse(feature.panelVisible)
    }
}
