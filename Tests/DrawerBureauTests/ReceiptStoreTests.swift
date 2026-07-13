import XCTest
@testable import DrawerBureau

@MainActor
final class ReceiptStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripThroughDiskPreservesEverything() {
        let store = ReceiptStore(directory: dir)
        // Whole-second timestamps: the store's JSON encoding is ISO 8601
        // without fractional seconds, so a `Date()` default would round-trip
        // lossy and flake this assertion.
        let link = ReceiptLink(
            textSnapshot: "Call the landlord",
            sectionDate: "2026-07-13",
            occurrence: 0,
            state: .inDrawer,
            position: ReceiptPosition(x: 12, y: 34),
            rotation: 0.05,
            stickySize: .title,
            createdAt: Date(timeIntervalSince1970: 900),
            printedAt: Date(timeIntervalSince1970: 1000)
        )
        store.add(link)

        let reloaded = ReceiptStore(directory: dir)
        XCTAssertEqual(reloaded.document.receipts, [link])
    }

    func testLifetimeFiledCounterSurvivesReload() {
        let store = ReceiptStore(directory: dir)
        let link = ReceiptLink(textSnapshot: "Ship the release", sectionDate: "2026-07-13")
        store.add(link)
        store.file(link.id)
        XCTAssertEqual(store.document.lifetimeFiled, 1)
        XCTAssertEqual(store.document.receipts.first?.state, .filed)

        let reloaded = ReceiptStore(directory: dir)
        XCTAssertEqual(reloaded.document.lifetimeFiled, 1)
        XCTAssertEqual(reloaded.document.receipts.first?.state, .filed)
    }

    func testMissingFileLoadsEmptyDocument() {
        let store = ReceiptStore(directory: dir)
        XCTAssertEqual(store.document, ReceiptDocument())
    }

    func testMalformedFileLoadsEmptyDocument() throws {
        try Data("not json".utf8).write(to: dir.appendingPathComponent("bureau-receipts.json"))
        let store = ReceiptStore(directory: dir)
        XCTAssertEqual(store.document, ReceiptDocument())
    }

    func testUpdateReplacesMatchingReceiptOnly() {
        let store = ReceiptStore(directory: dir)
        let a = ReceiptLink(textSnapshot: "a", sectionDate: "2026-07-13")
        let b = ReceiptLink(textSnapshot: "b", sectionDate: "2026-07-13")
        store.add(a)
        store.add(b)

        var moved = a
        moved.position = ReceiptPosition(x: 99, y: 1)
        store.update(moved)

        XCTAssertEqual(store.document.receipts.first { $0.id == a.id }?.position.x, 99)
        XCTAssertEqual(store.document.receipts.first { $0.id == b.id }?.position.x, 0)
    }

    func testRemoveDeletesReceipt() {
        let store = ReceiptStore(directory: dir)
        let link = ReceiptLink(textSnapshot: "a", sectionDate: "2026-07-13")
        store.add(link)
        store.remove(link.id)
        XCTAssertTrue(store.document.receipts.isEmpty)
    }

    /// Atomic write means every save leaves exactly the target file behind,
    /// never a partial or temp sibling from an interrupted write.
    func testAtomicWriteLeavesNoPartialFile() throws {
        let store = ReceiptStore(directory: dir)
        for i in 0..<5 {
            store.add(ReceiptLink(textSnapshot: "task \(i)", sectionDate: "2026-07-13", occurrence: i))
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents, ["bureau-receipts.json"])

        // The file that IS there must be whole, valid JSON, not a torn write.
        let data = try Data(contentsOf: store.receiptsFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try decoder.decode(ReceiptDocument.self, from: data))
    }
}
