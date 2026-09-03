import CoreGraphics
import XCTest
@testable import DrawerCore

/// The board's write path: what actually reaches board.json, in what order, and
/// off which thread.
@MainActor
final class BoardPersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Records every write in the order it lands, and can stall the first one so
    /// later work piles up behind it on the persistence queue.
    private final class WriteRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var writes: [Data] = []
        private var offMainCount = 0
        var stallFirstWrite: TimeInterval = 0
        private var stalled = false

        func record(_ data: Data) {
            let shouldStall = lock.withLock { () -> Bool in
                if stallFirstWrite > 0, !stalled { stalled = true; return true }
                return false
            }
            if shouldStall { Thread.sleep(forTimeInterval: stallFirstWrite) }
            lock.withLock {
                writes.append(data)
                if !Thread.isMainThread { offMainCount += 1 }
            }
        }

        var all: [Data] { lock.withLock { writes } }
        var count: Int { lock.withLock { writes.count } }
        var offMain: Int { lock.withLock { offMainCount } }
    }

    private func makeStore(
        debounce: TimeInterval = 0, recorder: WriteRecorder
    ) -> BoardStore {
        BoardStore(
            directory: dir,
            debounce: debounce,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                recorder.record(data)
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    private func titles(in data: Data) throws -> [String] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BoardDocument.self, from: data).items.compactMap(\.title)
    }

    /// The whole point of the debounce: a drag is dozens of mutations and one
    /// write.
    func testRapidMutationsCollapseIntoOneWrite() async throws {
        let recorder = WriteRecorder()
        let store = makeStore(debounce: 0.05, recorder: recorder)
        let item = store.addText(title: "a", body: "")
        for x in 1...20 {
            store.move(item.id, to: CGPoint(x: Double(x), y: 0))
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(recorder.count, 1, "a burst of drags must land as one write")
        XCTAssertEqual(store.document.items[0].x, 20)
    }

    /// Every queued write carries the document it was made from, and the newest
    /// one is the one left on disk.
    func testQueuedWritesLandInOrderAndNewestWins() async throws {
        let recorder = WriteRecorder()
        let store = makeStore(debounce: 0, recorder: recorder)
        store.addText(title: "one", body: "")
        try await Task.sleep(nanoseconds: 50_000_000)
        store.addText(title: "two", body: "")
        try await Task.sleep(nanoseconds: 50_000_000)
        store.addText(title: "three", body: "")
        try await Task.sleep(nanoseconds: 100_000_000)

        let landed = try recorder.all.map { try titles(in: $0) }
        XCTAssertEqual(landed.map(\.count), Array(1...landed.count), "writes went out of order: \(landed)")
        XCTAssertEqual(try titles(in: Data(contentsOf: store.boardFile)), ["one", "two", "three"])
    }

    /// saveNow is the teardown path: when it returns, the newest document is on
    /// disk, and nothing queued before it may overwrite it afterwards.
    func testSaveNowIsDurableAndNotOverwrittenByEarlierWork() async throws {
        let recorder = WriteRecorder()
        let store = makeStore(debounce: 0.2, recorder: recorder)
        store.addText(title: "old", body: "")
        store.addText(title: "new", body: "")
        store.saveNow()

        XCTAssertEqual(
            try titles(in: Data(contentsOf: store.boardFile)), ["old", "new"],
            "saveNow must have written before it returned")

        // Give the cancelled debounce every chance to fire late.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(
            try titles(in: Data(contentsOf: store.boardFile)), ["old", "new"],
            "an older snapshot overwrote the newest one")
    }

    /// `clear` used to write straight to disk while the queue still held an
    /// older board, which put the cleared items back a moment later.
    func testClearIsNotResurrectedByAWriteQueuedBeforeIt() async throws {
        let recorder = WriteRecorder()
        recorder.stallFirstWrite = 0.25
        let store = makeStore(debounce: 0, recorder: recorder)
        store.addText(title: "first", body: "")   // stalls the queue when it runs
        try await Task.sleep(nanoseconds: 20_000_000)
        store.addText(title: "second", body: "")  // piles up behind it

        try store.clear()
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(
            try titles(in: Data(contentsOf: store.boardFile)), [],
            "a write queued before clear() put the board back")
    }

    /// The encode is the expensive part of a save and must not run on the main
    /// thread for the debounced path.
    func testDebouncedEncodeRunsOffTheMainThread() async throws {
        let recorder = WriteRecorder()
        let store = makeStore(debounce: 0, recorder: recorder)
        store.addText(title: "off main", body: "")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.offMain, 1, "the debounced write ran on the main thread")
    }

    /// The guard that makes ordering safe regardless of how the queue is fed.
    func testWriteLogDropsAnOlderGeneration() {
        let log = WriteLog()
        XCTAssertTrue(log.claim(1))
        XCTAssertTrue(log.claim(3))
        XCTAssertFalse(log.claim(2), "an older snapshot must not overwrite a newer one")
        XCTAssertFalse(log.claim(3), "the same generation must not write twice")
        XCTAssertTrue(log.claim(4))
    }
}
