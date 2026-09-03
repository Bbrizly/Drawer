import CoreGraphics
import XCTest
@testable import DrawerCore

/// The board popover's size and load numbers. The cache used to key on items
/// alone while the numbers also depended on the board's name, its viewport and
/// the media on disk.
@MainActor
final class BoardMetricsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("media"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> BoardStore {
        BoardStore(
            directory: dir,
            debounce: 0,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in try data.write(to: url, options: .atomic) },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func testIdenticalInputsHitTheCache() {
        let store = makeStore()
        store.addText(title: "a", body: "")
        let board = store.document.activeBoard

        _ = store.metrics(for: board)
        let computes = store.metricsComputeCount
        _ = store.metrics(for: board)
        _ = store.metrics(for: board)

        XCTAssertEqual(store.metricsComputeCount, computes, "an unchanged board re-encoded")
    }

    func testRenamingTheBoardChangesTheReportedJSONSize() {
        let store = makeStore()
        store.addText(title: "a", body: "")
        let before = store.metrics(for: store.document.activeBoard).jsonBytes

        store.renameBoard(store.document.activeBoardID, to: "A considerably longer board name")
        let after = store.metrics(for: store.document.activeBoard).jsonBytes

        XCTAssertNotEqual(before, after, "the JSON size still reported the old name")
    }

    func testMovingTheCameraChangesTheReportedJSONSize() {
        let store = makeStore()
        store.addText(title: "a", body: "")
        let before = store.metrics(for: store.document.activeBoard).jsonBytes

        store.applyViewport(BoardViewport(x: 123.456, y: 789.012, zoom: 2.25))
        let after = store.metrics(for: store.document.activeBoard).jsonBytes

        XCTAssertNotEqual(before, after, "the JSON size still reported the old viewport")
    }

    func testReplacingAMediaFileRecomputesStorage() throws {
        let store = makeStore()
        let file = "media/pic.png"
        try Data(count: 100).write(to: dir.appendingPathComponent(file))
        store.addImage(
            file: file,
            naturalSize: CGSize(width: 10, height: 10),
            displaySize: CGSize(width: 10, height: 10),
            at: .zero
        )
        XCTAssertEqual(store.metrics(for: store.document.activeBoard).mediaBytes, 100)

        // Someone swaps the image outside the app. Nothing in the document
        // changed, so an items-keyed cache would report 100 forever.
        try Data(count: 4_096).write(to: dir.appendingPathComponent(file))
        XCTAssertEqual(store.metrics(for: store.document.activeBoard).mediaBytes, 4_096)
    }

    func testItemMutationInvalidatesItemDerivedMetrics() {
        let store = makeStore()
        let item = store.addText(title: "a", body: "")
        XCTAssertEqual(store.metrics(for: store.document.activeBoard).itemCount, 1)

        store.moveAndResize(item.id, to: CGRect(x: 0, y: 0, width: 400, height: 400))
        let metrics = store.metrics(for: store.document.activeBoard)
        XCTAssertEqual(metrics.canvasPointArea, 160_000)

        store.addText(title: "b", body: "")
        XCTAssertEqual(store.metrics(for: store.document.activeBoard).itemCount, 2)
    }
}
