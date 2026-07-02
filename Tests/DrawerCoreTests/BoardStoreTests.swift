import CoreGraphics
import XCTest
@testable import DrawerCore

@MainActor
final class BoardStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(
        debounce: TimeInterval = 0,
        onWrite: ((Data, URL) -> Void)? = nil
    ) -> BoardStore {
        BoardStore(
            directory: dir,
            debounce: debounce,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                onWrite?(data, url)
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func testBatchMoveAndDeleteAreOneUndoStep() {
        let store = makeStore()
        let a = store.addText(title: "a", body: "", at: .zero)
        let b = store.addText(title: "b", body: "", at: .zero)
        store.setPositions([a.id: CGPoint(x: 10, y: 20), b.id: CGPoint(x: 30, y: 40)])
        XCTAssertEqual(store.document.items.first { $0.id == a.id }?.x, 10)
        XCTAssertEqual(store.document.items.first { $0.id == b.id }?.y, 40)
        store.undo() // one step undoes both moves
        XCTAssertEqual(store.document.items.first { $0.id == a.id }?.x, 0)
        store.removeMany([a.id, b.id])
        XCTAssertEqual(store.document.items.count, 0)
        store.undo() // one step brings both back
        XCTAssertEqual(store.document.items.count, 2)
    }

    func testUndoRedoRoundTrips() {
        let store = makeStore()
        store.addText(title: "one", body: "")
        store.addText(title: "two", body: "")
        XCTAssertEqual(store.document.items.count, 2)
        store.undo()
        XCTAssertEqual(store.document.items.map(\.title), ["one"])
        store.undo()
        XCTAssertEqual(store.document.items.count, 0)
        store.redo()
        XCTAssertEqual(store.document.items.map(\.title), ["one"])
        // A fresh edit clears the redo stack.
        store.addText(title: "three", body: "")
        store.redo() // no-op now
        XCTAssertEqual(store.document.items.map(\.title), ["one", "three"])
    }

    func testAddTextAppendsTextItem() {
        let store = makeStore()
        let item = store.addText(title: "Buy milk", body: "2%")
        XCTAssertEqual(store.document.items.count, 1)
        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.title, "Buy milk")
        XCTAssertEqual(item.body, "2%")
    }

    func testAddTextEmptyBodyIsNil() {
        let store = makeStore()
        let item = store.addText(title: "Solo", body: "")
        XCTAssertNil(item.body)
    }

    func testAddImageAppendsImageItem() {
        let store = makeStore()
        let item = store.addImage(
            file: "media/x.png",
            naturalSize: CGSize(width: 800, height: 600),
            displaySize: CGSize(width: 360, height: 270),
            at: CGPoint(x: 10, y: 20)
        )
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.file, "media/x.png")
        XCTAssertEqual(item.width, 360, accuracy: 0.001)
    }

    func testMoveUpdatesPosition() {
        let store = makeStore()
        let item = store.addText(title: "a", body: "")
        store.move(item.id, to: CGPoint(x: 100, y: 200))
        XCTAssertEqual(store.document.items.first?.x, 100)
        XCTAssertEqual(store.document.items.first?.y, 200)
    }

    func testBringToFrontRaisesZAboveMax() {
        let store = makeStore()
        let a = store.addText(title: "a", body: "")
        let b = store.addText(title: "b", body: "")
        store.bringToFront(a.id)
        let za = store.document.items.first { $0.id == a.id }!.z
        let zb = store.document.items.first { $0.id == b.id }!.z
        XCTAssertGreaterThan(za, zb)
    }

    func testRemoveDeletesItem() {
        let store = makeStore()
        let a = store.addText(title: "a", body: "")
        store.remove(a.id)
        XCTAssertTrue(store.document.items.isEmpty)
    }

    func testRoundTripThroughDisk() {
        let store = makeStore()
        store.addText(title: "Idea", body: "ramble")
        store.addImage(
            file: "media/x.png",
            naturalSize: CGSize(width: 100, height: 100),
            displaySize: CGSize(width: 50, height: 50),
            at: CGPoint(x: 5, y: 6)
        )
        store.setViewport(BoardViewport(x: 12, y: 34, zoom: 1.5))
        store.saveNow()

        let reloaded = makeStore()
        reloaded.load()
        XCTAssertEqual(reloaded.document.items.count, 2)
        XCTAssertEqual(reloaded.document.viewport.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(reloaded.document.items.first?.title, "Idea")
    }

    func testLoadMalformedGivesEmptyBoard() throws {
        let file = dir.appendingPathComponent("board.json")
        try Data("not json".utf8).write(to: file)
        let store = makeStore()
        store.load()
        XCTAssertTrue(store.document.items.isEmpty)
    }

    func testRapidMutationsCollapseToOneWrite() {
        var writes = 0
        let store = makeStore(debounce: 0.05) { _, _ in writes += 1 }
        store.addText(title: "a", body: "")
        store.addText(title: "b", body: "")
        store.addText(title: "c", body: "")

        let exp = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(writes, 1, "debounce should collapse rapid mutations")
    }

    func testSaveNowWritesImmediately() {
        var writes = 0
        let store = makeStore(debounce: 10) { _, _ in writes += 1 }
        store.addText(title: "a", body: "")  // scheduled far in the future
        store.saveNow()
        XCTAssertEqual(writes, 1)
    }
}
