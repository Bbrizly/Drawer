import XCTest
@testable import DrawerCore

/// Round-trips through the REAL disk closures (diskRead/diskAppend/
/// diskOverwrite). Every other store test injects memory IO, so without these
/// the directory creation, file creation, and torn-line healing on disk never
/// execute anywhere.
final class JSONLStoreDiskTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-disk-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> JSONLStore<ActivitySample> {
        // Nested path: append must create the directory and the file.
        JSONLStore(fileURL: dir.appendingPathComponent("nested/raw.jsonl"))
    }

    private func sample(_ s: TimeInterval, _ title: String) -> ActivitySample {
        ActivitySample(
            ts: Date(timeIntervalSince1970: s), bundleID: "com.apple.dt.Xcode",
            appName: "Xcode", windowTitle: title)
    }

    func testAppendReadReplaceRoundTrip() throws {
        let store = store()
        XCTAssertEqual(store.all().count, 0) // missing file reads as empty
        try store.append(sample(0, "a"))
        try store.append(sample(60, "b"))
        XCTAssertEqual(store.all().map(\.windowTitle), ["a", "b"])
        try store.replaceAll([sample(60, "b")])
        XCTAssertEqual(store.all().map(\.windowTitle), ["b"])
        store.prune(now: Date(timeIntervalSince1970: 10 * 86_400))
        XCTAssertEqual(store.all().count, 0) // outside the 7-day window
    }

    func testAppendHealsTornFinalLine() throws {
        let store = store()
        try store.append(sample(0, "a"))
        // Simulate a crash mid-append: a partial record with no newline.
        let url = dir.appendingPathComponent("nested/raw.jsonl")
        var bytes = try Data(contentsOf: url)
        bytes.append(Data("{\"ts\":\"torn".utf8))
        try bytes.write(to: url)
        // The next append must add its own line, not concatenate onto the
        // torn one (which would make BOTH undecodable).
        try store.append(sample(60, "b"))
        XCTAssertEqual(store.all().map(\.windowTitle), ["a", "b"])
    }

    func testSnapshotStoreDiskRoundTripAndTornIndexRepair() throws {
        let store = SnapshotStore(directory: dir)
        let first = Data("## day\n- [ ] a\n".utf8)
        guard case .appended = try store.append(bytes: first, ts: Date(timeIntervalSince1970: 0)) else {
            return XCTFail("expected appended")
        }
        // Tear the index the way a crash mid-append would.
        let index = dir.appendingPathComponent("index.jsonl")
        var bytes = try Data(contentsOf: index)
        bytes.append(Data("{\"ts\":\"torn".utf8))
        try bytes.write(to: index)

        let second = Data("## day\n- [x] a\n".utf8)
        guard case .appended = try store.append(bytes: second, ts: Date(timeIntervalSince1970: 60)) else {
            return XCTFail("expected appended")
        }
        let records = store.readRange()
        XCTAssertEqual(records.count, 2, "torn line skipped, both real records intact")
        XCTAssertEqual(store.reconstruct(records[1]), .available(second))

        // Prune keeps the newest and garbage-collects the orphan blob.
        let result = try store.prune(keepLast: 1)
        XCTAssertEqual(result.kept, 1)
        XCTAssertEqual(result.deletedBlobs, 1)
        XCTAssertEqual(store.reconstruct(store.readRange()[0]), .available(second))
    }
}
