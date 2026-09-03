@testable import Drawer
import DrawerCore
import XCTest

/// Reconstructing and parsing snapshots away from the UI, and the cache that
/// used to grow to the whole 500-snapshot retention window.
final class HistoryLoaderTests: XCTestCase {
    /// In-memory blobs plus a read counter, so a test can prove a second load of
    /// the same hash never went back to disk.
    private final class Blobs: @unchecked Sendable {
        private let lock = NSLock()
        private var store: [String: Data] = [:]
        private(set) var reads = 0

        func put(_ hash: String, _ data: Data) { lock.withLock { store[hash] = data } }
        func read(_ hash: String) throws -> Data {
            try lock.withLock {
                reads += 1
                guard let data = store[hash] else { throw CocoaError(.fileReadNoSuchFile) }
                return data
            }
        }
        func resetReads() { lock.withLock { reads = 0 } }
    }

    private func makeStore(_ blobs: Blobs) -> SnapshotStore {
        SnapshotStore(io: SnapshotStoreIO(
            readIndex: { Data() },
            replaceIndex: { _ in },
            appendIndexLine: { _ in },
            blobExists: { _ in true },
            writeBlob: { _, _ in },
            readBlob: { try blobs.read($0) },
            listBlobs: { [] },
            deleteBlob: { _ in }
        ))
    }

    /// Adds a snapshot whose recorded hash really is the hash of its bytes.
    @discardableResult
    private func add(
        _ markdown: String, at ts: Date, to blobs: Blobs
    ) -> SnapshotRecord {
        let data = Data(markdown.utf8)
        let hash = SnapshotStore.sha256Hex(data)
        blobs.put(hash, data)
        return SnapshotRecord(ts: ts, hash: hash, bytes: data.count)
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + Double(offset) * 3_600)
    }

    func testRepeatedLoadsOfOneHashReuseTheParse() async {
        let blobs = Blobs()
        let record = add("## 2026-06-07\n- [ ] a\n", at: day(0), to: blobs)
        let loader = HistoryLoader(store: makeStore(blobs))

        let first = await loader.display(for: record, today: "2026-06-07")
        let second = await loader.display(for: record, today: "2026-06-07")

        XCTAssertEqual(first?.today.map(\.title), ["a"])
        XCTAssertEqual(second?.today.map(\.title), ["a"])
        XCTAssertEqual(blobs.reads, 1, "the second load went back to disk")
    }

    func testCorruptSnapshotStaysUnavailable() async {
        let blobs = Blobs()
        let data = Data("## 2026-06-07\n- [ ] a\n".utf8)
        // Recorded under a hash the bytes do not match: tampering or a torn write.
        blobs.put("deadbeef", data)
        let record = SnapshotRecord(ts: day(0), hash: "deadbeef", bytes: data.count)
        let loader = HistoryLoader(store: makeStore(blobs))

        let result = await loader.display(for: record, today: "2026-06-07")

        XCTAssertNil(result)
        // Cached as a known failure, so scrubbing back does not re-read it.
        _ = await loader.display(for: record, today: "2026-06-07")
        XCTAssertEqual(blobs.reads, 1)
    }

    func testCacheStaysWithinCapacity() async {
        let blobs = Blobs()
        let records = (0..<(HistoryLoader.capacity * 2)).map { i in
            add("## 2026-06-07\n- [ ] task \(i)\n", at: day(i), to: blobs)
        }
        let loader = HistoryLoader(store: makeStore(blobs))

        for record in records {
            _ = await loader.display(for: record, today: "2026-06-07")
        }

        let cached = await loader.cachedCount
        XCTAssertEqual(cached, HistoryLoader.capacity)
    }

    /// The old loader put every reconstructed blob into a dictionary that the
    /// eviction order never touched, so one summary pinned the whole window.
    func testSummaryDoesNotRetainEverySnapshot() async {
        let blobs = Blobs()
        let records = (0..<200).map { i in
            add("## 2026-06-07\n- [ ] task \(i % 7)\n", at: day(i), to: blobs)
        }
        let loader = HistoryLoader(store: makeStore(blobs))

        let summary = await loader.dailySummary(for: records)

        XCTAssertFalse(summary.isEmpty)
        let cached = await loader.cachedCount
        XCTAssertEqual(cached, 0, "summary generation retained \(cached) reconstructed snapshots")
    }

    func testSummaryIsCachedForTheSameRecords() async {
        let blobs = Blobs()
        let records = (0..<5).map { i in
            add("## 2026-06-07\n- [ ] task \(i)\n", at: day(i), to: blobs)
        }
        let loader = HistoryLoader(store: makeStore(blobs))

        _ = await loader.dailySummary(for: records)
        blobs.resetReads()
        _ = await loader.dailySummary(for: records)

        XCTAssertEqual(blobs.reads, 0, "an unchanged record list rebuilt the summary")
    }

    func testDayRollReparsesTheSameBytes() async {
        let blobs = Blobs()
        let record = add("## 2026-06-07\n- [ ] a\n", at: day(0), to: blobs)
        let loader = HistoryLoader(store: makeStore(blobs))

        let sunday = await loader.display(for: record, today: "2026-06-07")
        let monday = await loader.display(for: record, today: "2026-06-08")

        XCTAssertEqual(sunday?.today.map(\.title), ["a"])
        XCTAssertEqual(monday?.today.map(\.title), [], "the parse was cached across a day change")
        XCTAssertEqual(monday?.carried.map(\.title), ["a"])
    }
}

/// The scrubber's snapshot state. Loading is deliberately its own case: the old
/// view showed "This snapshot is unavailable." for the whole async load.
final class HistorySnapshotStateTests: XCTestCase {
    private var display: HistoryDisplay {
        HistoryDisplay(
            today: [], carried: [], upcoming: [], upcomingDate: nil, backlog: [], archive: [])
    }

    func testLoadingIsNotUnavailable() {
        let state = HistorySnapshotState.loading(hash: "abc")
        XCTAssertNil(state.display(for: "abc"))
        XCTAssertFalse(state.isUnavailable(for: "abc"), "a loading snapshot read as corrupt")
    }

    func testIdleIsNotUnavailable() {
        XCTAssertFalse(HistorySnapshotState.idle.isUnavailable(for: "abc"))
    }

    func testMissingSnapshotIsUnavailable() {
        let state = HistorySnapshotState.unavailable(hash: "abc")
        XCTAssertTrue(state.isUnavailable(for: "abc"))
        XCTAssertNil(state.display(for: "abc"))
    }

    /// The slider moved on. Whatever finished loading for the previous step must
    /// not be drawn under the new one.
    func testLoadedSnapshotIsNotShownForADifferentSelection() {
        let state = HistorySnapshotState.loaded(hash: "old", display)
        XCTAssertNotNil(state.display(for: "old"))
        XCTAssertNil(state.display(for: "new"), "the previous snapshot was shown as the new one")
        XCTAssertFalse(state.isUnavailable(for: "new"))
    }

    func testUnavailableForOneSnapshotDoesNotCondemnAnother() {
        let state = HistorySnapshotState.unavailable(hash: "old")
        XCTAssertFalse(state.isUnavailable(for: "new"))
    }
}
