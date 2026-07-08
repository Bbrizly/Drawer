import XCTest
@testable import DrawerCore

/// In-memory snapshot IO so the store's logic is tested without touching disk.
private final class MemStore: @unchecked Sendable {
    var indexLines: [String] = []
    var blobs: [String: Data] = [:]
    /// Simulates a transient disk failure (EPERM/EIO) on the index read.
    var indexReadFails = false

    func io() -> SnapshotStoreIO {
        SnapshotStoreIO(
            readIndex: {
                if self.indexReadFails { throw CocoaError(.fileReadUnknown) }
                return Data((self.indexLines.isEmpty ? "" : self.indexLines.joined(separator: "\n") + "\n").utf8)
            },
            replaceIndex: { data in
                let text = String(data: data, encoding: .utf8) ?? ""
                self.indexLines = text.split(separator: "\n").map(String.init)
            },
            appendIndexLine: { data in
                let line = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines)
                if !line.isEmpty { self.indexLines.append(line) }
            },
            blobExists: { self.blobs[$0] != nil },
            writeBlob: { self.blobs[$0] = $1 },
            readBlob: { guard let d = self.blobs[$0] else { throw CocoaError(.fileReadNoSuchFile) }; return d },
            listBlobs: { Array(self.blobs.keys) },
            deleteBlob: { self.blobs[$0] = nil })
    }
}

private let t0 = Date(timeIntervalSince1970: 0)
private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

final class SnapshotStoreTests: XCTestCase {
    func testAppendWritesBlobAndIndexAndReconstructs() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        let bytes = Data("## 2026-07-06\n- [ ] a\n".utf8)
        let result = try store.append(bytes: bytes, ts: t0)
        guard case .appended = result else { return XCTFail("expected appended") }
        XCTAssertEqual(mem.indexLines.count, 1)
        XCTAssertEqual(mem.blobs.count, 1)
        let records = store.readRange()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].bytes, bytes.count)
        XCTAssertEqual(store.reconstruct(records[0]), .available(bytes))
    }

    func testIdenticalContentDedupes() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        let bytes = Data("same".utf8)
        _ = try store.append(bytes: bytes, ts: t0)
        let second = try store.append(bytes: bytes, ts: t(1))
        XCTAssertEqual(second, .duplicate)
        XCTAssertEqual(mem.indexLines.count, 1) // no second line
        XCTAssertEqual(mem.blobs.count, 1)
    }

    func testPruneFailsClosedWhenIndexUnreadable() throws {
        // A transient index read error must abort prune, not read as "empty
        // history" and garbage-collect every blob.
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        _ = try store.append(bytes: Data("a".utf8), ts: t0)
        _ = try store.append(bytes: Data("b".utf8), ts: t(1))
        mem.indexReadFails = true
        XCTAssertThrowsError(try store.prune(keepLast: 1))
        XCTAssertEqual(mem.blobs.count, 2, "no blob may be deleted on a failed read")
        XCTAssertEqual(mem.indexLines.count, 2, "index must not be rewritten on a failed read")
    }

    func testAppendFailsClosedWhenIndexUnreadable() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        _ = try store.append(bytes: Data("a".utf8), ts: t0)
        mem.indexReadFails = true
        XCTAssertThrowsError(try store.append(bytes: Data("b".utf8), ts: t(1)))
    }

    func testReconstructUnavailableWhenBlobMissing() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        _ = try store.append(bytes: Data("x".utf8), ts: t0)
        let record = store.readRange()[0]
        mem.blobs.removeAll()  // simulate a tampered/missing blob
        XCTAssertEqual(store.reconstruct(record), .unavailable)
    }

    func testReconstructRejectsCorruptedBlob() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        _ = try store.append(bytes: Data("real".utf8), ts: t0)
        let record = store.readRange()[0]
        mem.blobs[record.hash] = Data("tampered".utf8)  // wrong content under the hash
        XCTAssertEqual(store.reconstruct(record), .unavailable)
    }

    func testPruneSurfacesBlobListingError() {
        var io = MemStore().io()
        struct DiskError: Error {}
        io = SnapshotStoreIO(
            readIndex: io.readIndex, replaceIndex: io.replaceIndex, appendIndexLine: io.appendIndexLine,
            blobExists: io.blobExists, writeBlob: io.writeBlob, readBlob: io.readBlob,
            listBlobs: { throw DiskError() }, deleteBlob: io.deleteBlob)
        let store = SnapshotStore(io: io)
        XCTAssertThrowsError(try store.prune(keepLast: 1)) { XCTAssertTrue($0 is DiskError) }
    }

    func testPruneKeepsLastN() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        for i in 0..<5 { _ = try store.append(bytes: Data("state\(i)".utf8), ts: t(Double(i))) }
        let result = try store.prune(keepLast: 2)
        XCTAssertEqual(result.kept, 2)
        XCTAssertEqual(store.readRange().map(\.bytes).count, 2)
        XCTAssertEqual(mem.blobs.count, 2) // 3 unreferenced blobs GC'd
    }

    // MARK: GC-by-reachability — the silent-corruption guard

    func testPruneKeepsBlobStillReferencedByASurvivingLine() throws {
        // Two index lines share hash A; only one is pruned. Blob A must survive.
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        let a = SnapshotStore.sha256Hex(Data("A".utf8))
        mem.blobs[a] = Data("A".utf8)
        mem.indexLines = [line(ts: t(1), hash: a, bytes: 1), line(ts: t(2), hash: a, bytes: 1)]
        _ = try store.prune(keepLast: 1)
        XCTAssertEqual(store.readRange().count, 1)
        XCTAssertNotNil(mem.blobs[a], "blob A is still referenced by the surviving line")
    }

    func testPruneDeletesBlobWhenLastReferenceRemoved() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        let a = SnapshotStore.sha256Hex(Data("A".utf8))
        let b = SnapshotStore.sha256Hex(Data("B".utf8))
        mem.blobs[a] = Data("A".utf8)
        mem.blobs[b] = Data("B".utf8)
        mem.indexLines = [line(ts: t(1), hash: a, bytes: 1), line(ts: t(2), hash: b, bytes: 1)]
        _ = try store.prune(keepLast: 1)
        XCTAssertEqual(store.readRange().map(\.hash), [b])
        XCTAssertNil(mem.blobs[a], "blob A had its last reference removed")
        XCTAssertNotNil(mem.blobs[b])
    }

    // MARK: reconstruct-and-parse

    func testSnapshotBytesParseWithTodoParser() throws {
        let mem = MemStore()
        let store = SnapshotStore(io: mem.io())
        _ = try store.append(bytes: Data("## 2026-07-06\n- [ ] a\n- [x] b\n".utf8), ts: t0)
        guard case let .available(bytes) = store.reconstruct(store.readRange()[0]) else {
            return XCTFail("unavailable")
        }
        let sections = TodoParser.parse(String(data: bytes, encoding: .utf8)!)
        XCTAssertEqual(sections.first?.items.map(\.title), ["a", "b"])
    }

    private func line(ts: Date, hash: String, bytes: Int) -> String {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        return String(decoding: try! enc.encode(SnapshotRecord(ts: ts, hash: hash, bytes: bytes)), as: UTF8.self)
    }
}

final class QuietPeriodDebouncerTests: XCTestCase {
    func testBurstYieldsOneCapture() {
        var d = QuietPeriodDebouncer(quietInterval: 2)
        d.change(at: t(0)); d.change(at: t(1)); d.change(at: t(2))
        XCTAssertFalse(d.dueActions(at: t(3.9)))
        XCTAssertTrue(d.dueActions(at: t(4.0)))
        XCTAssertFalse(d.dueActions(at: t(4.1))) // consumed
    }

    func testSpacedChangesYieldSeparateCaptures() {
        var d = QuietPeriodDebouncer(quietInterval: 2)
        d.change(at: t(0))
        XCTAssertTrue(d.dueActions(at: t(2)))
        d.change(at: t(5))
        XCTAssertTrue(d.dueActions(at: t(7)))
    }
}
