import XCTest
@testable import DrawerCore

/// Two things the async file pipeline had to earn: a queued edit survives the
/// app quitting, and a second command on a row still lands when the first one
/// has already rewritten that row's text.
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

    // MARK: durability on quit

    /// The quit path is synchronous and the process dies when it returns, so a
    /// toggle made a keystroke earlier has to be on disk by then.
    func testFlushPutsAPendingToggleOnDiskBeforeItReturns() async throws {
        try write("## 2026-06-07\n- [ ] one\n")
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { try Data(contentsOf: $0) },
            // A slow disk, so quitting without the flush really would lose it.
            writeData: { data, url in
                Thread.sleep(forTimeInterval: 0.2)
                try data.write(to: url, options: .atomic)
            }
        )
        store.reload()
        await store.settle()

        store.toggle(store.todayItems[0])
        store.flushPendingWrites()

        XCTAssertEqual(try text(), "## 2026-06-07\n- [x] one\n")
        await store.settle()
    }

    /// A whole burst, not just the newest one, and in the order it was made.
    func testFlushPutsEveryQueuedEditOnDisk() async throws {
        let store = try await loaded("""
        ## 2026-06-07
        - [ ] one
        - [ ] two
        - [ ] three
        """)
        let items = store.todayItems

        store.toggle(items[0])
        store.rename(items[1], to: "two renamed")
        store.setNote(items[2], "a note")
        store.add("four")
        store.flushPendingWrites()

        let result = try text()
        XCTAssertTrue(result.contains("- [x] one"), result)
        XCTAssertTrue(result.contains("- [ ] two renamed"), result)
        XCTAssertTrue(result.contains("    a note"), result)
        XCTAssertTrue(result.contains("- [ ] four"), result)
        await store.settle()
    }

    func testFlushWithNothingQueuedReturnsAtOnce() async throws {
        let store = try await loaded("## 2026-06-07\n- [ ] one\n")
        store.flushPendingWrites()
        XCTAssertEqual(try text(), "## 2026-06-07\n- [ ] one\n")
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

    /// A note line that happens to mention a checkbox is not a task. Counting
    /// it as one shifts every row below it onto its neighbour.
    func testACheckboxInsideANoteDoesNotShiftPositions() async throws {
        let store = try await loaded("""
        ## 2026-06-07
        - [ ] one
            remember to - [ ] buy milk
        - [ ] two
        """)
        let two = store.todayItems[1]

        store.toggle(two)
        store.toggle(two)
        await store.settle()

        let result = try text()
        XCTAssertTrue(result.contains("- [ ] one"), result)
        XCTAssertTrue(result.contains("    remember to - [ ] buy milk"), result)
        XCTAssertTrue(result.contains("- [ ] two"), result)
    }

    /// An insert lands at the end of the FIRST heading with that key, while the
    /// parser numbers across every heading sharing it. So an add renumbers a
    /// repeated section, and nothing queued behind it may trust a position.
    func testAnAddDisarmsPositionsInARepeatedSection() async throws {
        let store = try await loaded("""
        ## 2026-06-07
        - [ ] one

        ## 2026-06-07
        - [ ] two
        - [ ] three
        """)
        let three = store.todayItems[2]

        store.add("inserted")
        store.toggle(three)
        await store.settle()

        let result = try text()
        XCTAssertTrue(result.contains("- [x] three"), "the toggle landed elsewhere: \(result)")
        XCTAssertTrue(result.contains("- [ ] two"), result)
        XCTAssertTrue(result.contains("- [ ] one"), result)
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

    /// The dangerous shape: two commands queued on one row, and an outside
    /// editor inserts a row before either runs. The first falls back to the
    /// text and lands correctly. The second must not then read the first's
    /// write as proof that positions are still good.
    func testAnOutsideEditAheadOfABurstDisarmsTheRestOfIt() async throws {
        try write("## 2026-06-07\n- [ ] A\n- [ ] B\n- [ ] C\n")
        var reads = 0
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { url in
                reads += 1
                // Read 1 is the opening reload. Read 2 is the first command's,
                // and an outside editor gets in just before it.
                if reads == 2 {
                    try "## 2026-06-07\n- [ ] X\n- [ ] A\n- [ ] B\n- [ ] C\n"
                        .write(to: url, atomically: true, encoding: .utf8)
                }
                return try Data(contentsOf: url)
            },
            writeData: { data, url in try data.write(to: url, options: .atomic) }
        )
        store.reload()
        await store.settle()
        let c = store.todayItems[2]

        store.toggle(c)
        store.toggle(c)
        await store.settle()

        // Untrusted, the first tap finds C by text and the second finds nothing
        // and reloads. Trusted, both would land on whatever row 2 has become.
        let result = try text()
        XCTAssertTrue(result.contains("- [x] C"), "the taps did not land on C: \(result)")
        XCTAssertTrue(result.contains("- [ ] B"), "a tap landed on B: \(result)")
        XCTAssertTrue(result.contains("- [ ] X"), result)
        XCTAssertTrue(result.contains("- [ ] A"), result)
    }

    /// A delete's shift stops applying the moment its own publish renumbers the
    /// visible rows, not when the whole queue happens to drain.
    func testADeleteStopsShiftingOnceItHasPublished() async throws {
        try write("""
        ## 2026-06-07
        - [ ] one
        - [ ] two
        - [ ] three
        - [ ] four
        """)
        var reads = 0
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { url in
                reads += 1
                // Read 4 is the reload queued behind the delete. Holding it up
                // keeps the queue busy after the delete has published.
                if reads == 4 { Thread.sleep(forTimeInterval: 0.4) }
                return try Data(contentsOf: url)
            },
            writeData: { data, url in try data.write(to: url, options: .atomic) }
        )
        store.reload()
        await store.settle()

        store.delete(store.todayItems[0])
        store.reload()  // keeps the queue busy past the delete's publish

        var spins = 0
        while store.todayItems.count == 4, spins < 500 {
            try? await Task.sleep(nanoseconds: 2_000_000)
            spins += 1
        }
        XCTAssertEqual(store.todayItems.map(\.title), ["two", "three", "four"])

        store.toggle(store.todayItems[1])  // three, in the renumbered display
        await store.settle()

        let result = try text()
        XCTAssertTrue(result.contains("- [ ] two"), "the toggle landed on two: \(result)")
        XCTAssertTrue(result.contains("- [x] three"), result)
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
