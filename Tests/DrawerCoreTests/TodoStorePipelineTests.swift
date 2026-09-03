import XCTest
@testable import DrawerCore

/// The serialized off-main file pipeline. Every read, write, sweep and parse
/// now happens on `TodoFileWorker`; these pin the correctness the main-actor
/// version had, plus the ordering the queue is supposed to guarantee.
@MainActor
final class TodoStorePipelineTests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("2 Drawer.md")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func text() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func makeStore() -> TodoStore {
        TodoStore(fileURL: file, todayProvider: { "2026-06-07" })
    }

    /// Three toggles in a row must reach the file in the order they were made.
    /// Each one reads the file it is about to change, so an out-of-order run
    /// silently drops the edits that ran early.
    func testRapidMutationsKeepTheirOrderAndLoseNothing() async throws {
        try """
        ## 2026-06-07
        - [ ] one
        - [ ] two
        - [ ] three
        """.write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        await store.settle()

        let items = store.todayItems
        store.toggle(items[0])
        store.rename(items[1], to: "two renamed")
        store.toggle(items[2])
        await store.settle()

        let result = try text()
        XCTAssertTrue(result.contains("- [x] one"), result)
        XCTAssertTrue(result.contains("- [ ] two renamed"), result)
        XCTAssertTrue(result.contains("- [x] three"), result)
        XCTAssertEqual(store.todayItems.map(\.title), ["one", "two renamed", "three"])
    }

    /// A reload asked for before an edit must not publish over the edit's
    /// result, even though its disk read is slower.
    func testReloadQueuedBeforeAMutationDoesNotPublishOverIt() async throws {
        try "## 2026-06-07\n- [ ] slow\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        await store.settle()

        store.reload()                     // queued first
        store.toggle(store.todayItems[0])  // queued second, must win
        await store.settle()

        XCTAssertTrue(store.todayItems[0].isDone)
        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] slow\n")
    }

    /// The CAS re-read is the whole safety net for an external editor saving
    /// between our compute read and our write.
    func testExternalWriteBetweenReadAndCASRereadIsPreserved() async throws {
        let original = "## 2026-06-07\n- [ ] A\n"
        let edited = "## 2026-06-07\n- [ ] A\n- [ ] B\n"
        var reads = 0
        var written: Data?
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { _ in
                reads += 1
                return Data((reads <= 2 ? original : edited).utf8)
            },
            writeData: { data, _ in written = data }
        )
        store.reload()
        await store.settle()
        store.toggle(store.todayItems[0])
        await store.settle()

        let result = try XCTUnwrap(written.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(result.contains("- [x] A"), result)
        XCTAssertTrue(result.contains("- [ ] B"), "the concurrent external add was clobbered")
    }

    /// Work already in flight against the old file must not publish its tasks
    /// after the store has been pointed somewhere else.
    func testUpdateFileURLDropsResultsFromTheOldFile() async throws {
        try "## 2026-06-07\n- [ ] from A\n".write(to: file, atomically: true, encoding: .utf8)
        let fileB = dir.appendingPathComponent("B.md")
        try "## 2026-06-07\n- [ ] from B\n".write(to: fileB, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.reload()          // still queued against file A
        store.updateFileURL(fileB)
        await store.settle()

        XCTAssertEqual(store.todayItems.map(\.title), ["from B"])
        XCTAssertEqual(store.fileURL, fileB)
    }

    /// The watcher fires on our own write. Reloading from it must not re-parse
    /// or re-publish.
    func testSelfWriteIsSuppressedOnTheFollowingReload() async throws {
        try "## 2026-06-07\n- [ ] a\n".write(to: file, atomically: true, encoding: .utf8)
        var reads = 0
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { url in
                reads += 1
                return try Data(contentsOf: url)
            },
            writeData: { data, url in try data.write(to: url, options: .atomic) }
        )
        store.reload()
        await store.settle()
        store.toggle(store.todayItems[0])
        await store.settle()
        let afterEdit = store.todayItems

        // What the directory watcher does the moment our own write lands.
        store.reload()
        await store.settle()

        XCTAssertEqual(store.todayItems, afterEdit)
        XCTAssertTrue(store.todayItems[0].isDone)
        XCTAssertEqual(reads, 4, "reads: reload, commit read, commit CAS re-read, watcher reload")
    }

    /// A sibling file in the watched directory saving fires a reload for a
    /// drawer file that did not change.
    func testSiblingWatcherEventPublishesNothing() async throws {
        try "## 2026-06-07\n- [ ] a\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        await store.settle()
        let first = store.todayItems

        store.reload()
        await store.settle()

        XCTAssertEqual(store.todayItems, first)
    }

    /// Done tasks past the keep window get swept into Archive on load, which
    /// writes the file and displays the swept version, not the version read.
    func testArchiveSweepWritesAndDisplaysTheSweptFile() async throws {
        try """
        ## 2026-05-01
        - [x] long done

        ## 2026-06-07
        - [ ] today
        """.write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        await store.settle()

        let swept = try text()
        XCTAssertTrue(swept.contains("## Archive"), swept)
        XCTAssertEqual(store.todayItems.map(\.title), ["today"])
        XCTAssertTrue(store.archiveItems.contains { $0.title == "long done" })
    }

    func testMissingFileReportsItsOwnStatus() async {
        let store = makeStore()
        store.reload()
        await store.settle()

        XCTAssertEqual(store.statusMessage, "No drawer file yet")
        XCTAssertEqual(store.todayItems, [])
    }

    func testUnreadableFileIsNotReportedAsMissing() async {
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { _ in throw CocoaError(.fileReadNoPermission) },
            writeData: { data, url in try data.write(to: url, options: .atomic) }
        )
        store.reload()
        await store.settle()

        XCTAssertEqual(store.statusMessage, "Could not read drawer file")
    }

    func testFailedInsertSaysSoAndLeavesTheFileAlone() async throws {
        try "## 2026-06-07\n- [ ] a\n".write(to: file, atomically: true, encoding: .utf8)
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { try Data(contentsOf: $0) },
            writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )
        store.addTask("nope", toSectionKey: "backlog", displayHeading: "Backlog")
        await store.settle()

        XCTAssertEqual(store.statusMessage, "Could not save drawer file")
        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] a\n")
    }

    /// A toggle against a line that no longer exists never guesses: it reloads
    /// what is really on disk.
    func testStaleMutationFallsBackToAReload() async throws {
        try "## 2026-06-07\n- [ ] original\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        await store.settle()
        let stale = store.todayItems[0]

        try "## 2026-06-07\n- [ ] rewritten\n".write(to: file, atomically: true, encoding: .utf8)
        store.toggle(stale)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] rewritten\n")
        XCTAssertEqual(store.todayItems.map(\.title), ["rewritten"])
        XCTAssertNil(store.statusMessage)
    }

    /// Nothing in the pipeline may read or write the file on the main thread.
    func testFileWorkDoesNotRunOnTheMainThread() async throws {
        try "## 2026-06-07\n- [ ] a\n".write(to: file, atomically: true, encoding: .utf8)
        var mainThreadReads = 0
        var mainThreadWrites = 0
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { url in
                if Thread.isMainThread { mainThreadReads += 1 }
                return try Data(contentsOf: url)
            },
            writeData: { data, url in
                if Thread.isMainThread { mainThreadWrites += 1 }
                try data.write(to: url, options: .atomic)
            }
        )
        store.reload()
        await store.settle()
        store.toggle(store.todayItems[0])
        await store.settle()

        XCTAssertEqual(mainThreadReads, 0, "the drawer file was read on the main thread")
        XCTAssertEqual(mainThreadWrites, 0, "the drawer file was written on the main thread")
    }
}
