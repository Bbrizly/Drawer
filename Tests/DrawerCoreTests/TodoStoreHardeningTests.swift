import XCTest
@testable import DrawerCore

/// A second command on a row still has to land when the first one has already
/// rewritten that row's text.
@MainActor
final class TodoStoreHardeningTests: XCTestCase {
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

    private func write(_ contents: String) throws {
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    private func makeStore() -> TodoStore {
        TodoStore(fileURL: file, todayProvider: { "2026-06-07" })
    }

    private func loaded(_ contents: String) async throws -> TodoStore {
        try write(contents)
        let store = makeStore()
        store.reload()
        await store.settle()
        return store
    }

    // MARK: rapid commands on the same row

    /// Both toggles were made against the same displayed row, so the second one
    /// is holding a line the first one has already rewritten. It used to fail
    /// to find it and fall back to a reload, quietly eating the second tap.
    func testToggleTwiceLandsTwice() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] task\n")
        let item = store.todayItems[0]

        store.toggle(item)
        store.toggle(item)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] task\n")
        XCTAssertFalse(store.todayItems[0].isDone)
    }

    func testToggleThreeTimesLandsThreeTimes() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] task\n")
        let item = store.todayItems[0]

        store.toggle(item)
        store.toggle(item)
        store.toggle(item)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] task\n")
        XCTAssertTrue(store.todayItems[0].isDone)
    }

    func testToggleThenInProgressEndsInProgress() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] task\n")
        let item = store.todayItems[0]

        store.toggle(item)
        store.setInProgress(item, true)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [/] task\n")
        XCTAssertTrue(store.todayItems[0].isInProgress)
    }

    func testRenameThenToggleTogglesTheRenamedTask() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] task\n")
        let item = store.todayItems[0]

        store.rename(item, to: "renamed")
        store.toggle(item)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] renamed\n")
    }

    func testNoteThenToggleTogglesTheSameTask() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] task\n- [ ] other\n")
        let item = store.todayItems[0]

        store.setNote(item, "why it matters")
        store.toggle(item)
        await store.settle()

        XCTAssertEqual(try text(), """
        ## 2026-06-07
        - [x] task
            why it matters
        - [ ] other

        """)
    }

    /// Two lines that read the same are told apart by position, so a burst on
    /// one of them never wanders onto its twin.
    func testDuplicateLinesStayDistinctAcrossABurst() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] dup\n- [ ] dup\n")
        let items = store.todayItems

        store.toggle(items[1])
        store.toggle(items[1])
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] dup\n- [ ] dup\n")
    }

    func testEachDuplicateCanBeToggledInOneBurst() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] dup\n- [ ] dup\n")
        let items = store.todayItems

        store.toggle(items[0])
        store.toggle(items[1])
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] dup\n- [x] dup\n")
    }

    /// A delete queued in front of a toggle moves every row below it up one.
    /// Without that shift the toggle lands a row too low.
    func testDeleteQueuedAheadOfAToggleShiftsItsRow() async throws {
        let store = try await loaded("""
        ## 2026-06-07
        - [ ] one
        - [ ] two
        - [ ] three
        - [ ] four
        """)
        let items = store.todayItems

        store.delete(items[0])
        store.toggle(items[2])
        await store.settle()

        let result = try text()
        XCTAssertFalse(result.contains("one"), result)
        XCTAssertTrue(result.contains("- [x] three"), result)
        XCTAssertTrue(result.contains("- [ ] four"), result)
    }

    // MARK: outside editors

    /// Position is only trusted while this app is the only thing that has
    /// written the file. Once an editor replaces the target, the command has to
    /// fail into a reload rather than hit the row that took its place.
    func testAnExternallyReplacedTargetDoesNotHitItsNeighbour() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] first\n- [ ] second\n")
        let stale = store.todayItems[1]

        try write("## 2026-06-07\n- [ ] first\n- [ ] third\n")
        store.toggle(stale)
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] first\n- [ ] third\n")
        XCTAssertEqual(store.todayItems.map(\.title), ["first", "third"])
    }

    /// Same, but the outside edit lands in the middle of one of our own bursts,
    /// which is the case where a trusted position would be at its most wrong.
    func testAnOutsideEditMidBurstDropsPositionTrust() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] first\n- [ ] second\n")
        let items = store.todayItems

        store.toggle(items[0])
        await store.settle()
        // Our write landed; now something else rewrites the row underneath.
        try write("## 2026-06-07\n- [x] first\n- [ ] replaced\n")

        store.toggle(items[1])
        await store.settle()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] first\n- [ ] replaced\n")
    }
}
