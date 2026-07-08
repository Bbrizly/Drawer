import XCTest
@testable import DrawerCore

@MainActor
final class TodoStoreTests: XCTestCase {
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

    private func makeStore() -> TodoStore {
        TodoStore(fileURL: file, todayProvider: { "2026-06-07" })
    }

    func testLoadsTodayAndCarried() throws {
        try """
        ## 2026-06-05
        - [ ] carried task
        ## 2026-06-07
        - [ ] today task
        """.write(to: file, atomically: true, encoding: .utf8)

        let store = makeStore()
        store.reload()
        XCTAssertEqual(store.todayItems.map(\.title), ["today task"])
        XCTAssertEqual(store.carriedItems.map(\.title), ["carried task"])
        XCTAssertNil(store.statusMessage)
    }

    func testMissingFileShowsEmptyState() {
        let store = makeStore()
        store.reload()
        XCTAssertEqual(store.todayItems, [])
        XCTAssertEqual(store.carriedItems, [])
        XCTAssertNotNil(store.statusMessage)
    }

    func testToggleWritesFileAndUpdatesItems() throws {
        try "## 2026-06-07\n- [ ] flip me\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()

        store.toggle(store.todayItems[0])

        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            "## 2026-06-07\n- [x] flip me\n"
        )
        XCTAssertTrue(store.todayItems[0].isDone)
    }

    func testUpdateFileURLSwitchesSource() throws {
        try "## 2026-06-07\n- [ ] from A\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.start()
        XCTAssertEqual(store.todayItems.map(\.title), ["from A"])

        let fileB = dir.appendingPathComponent("B.md")
        try "## 2026-06-07\n- [ ] from B\n".write(to: fileB, atomically: true, encoding: .utf8)
        store.updateFileURL(fileB)

        XCTAssertEqual(store.todayItems.map(\.title), ["from B"])
        store.stop()
    }

    func testToggleStaleItemAbortsAndReloads() throws {
        try "## 2026-06-07\n- [ ] original\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        let stale = store.todayItems[0]

        // External edit replaces the line before the user clicks.
        try "## 2026-06-07\n- [ ] rewritten\n".write(to: file, atomically: true, encoding: .utf8)

        store.toggle(stale)

        // File untouched by the toggle; view reloaded to current truth.
        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            "## 2026-06-07\n- [ ] rewritten\n"
        )
        XCTAssertEqual(store.todayItems.map(\.title), ["rewritten"])
    }

    func testToggleOnlyChangesItemsDateSection() throws {
        try """
        ## 2026-06-05
        - [ ] same
        ## 2026-06-07
        - [ ] same
        """.write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()

        store.toggle(store.todayItems[0])

        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            """
            ## 2026-06-05
            - [ ] same
            ## 2026-06-07
            - [x] same
            """
        )
    }

    func testExternalRestoreOfPreviousAppWriteReloads() throws {
        try "## 2026-06-07\n- [ ] first\n".write(to: file, atomically: true, encoding: .utf8)
        let store = makeStore()
        store.reload()
        store.toggle(store.todayItems[0])
        let appWrite = try Data(contentsOf: file)

        try "## 2026-06-07\n- [ ] external\n".write(
            to: file, atomically: true, encoding: .utf8
        )
        store.reload()
        XCTAssertEqual(store.todayItems.map(\.title), ["external"])

        try appWrite.write(to: file, options: .atomic)
        store.reload()

        XCTAssertEqual(store.todayItems.map(\.title), ["first"])
        XCTAssertTrue(store.todayItems[0].isDone)
    }

    func testCalendarDayChangeReloadsSections() async throws {
        try """
        ## 2026-06-07
        - [ ] sunday
        ## 2026-06-08
        - [ ] monday
        """.write(to: file, atomically: true, encoding: .utf8)
        var today = "2026-06-07"
        let store = TodoStore(fileURL: file, todayProvider: { today })
        store.start()
        XCTAssertEqual(store.todayItems.map(\.title), ["sunday"])

        today = "2026-06-08"
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        await Task.yield()

        XCTAssertEqual(store.todayItems.map(\.title), ["monday"])
        store.stop()
    }

    func testWriteDayPlanCommitsAndRecomputesOnConcurrentEdit() throws {
        try "## 2026-06-07\n- [ ] existing\n".write(to: file, atomically: true, encoding: .utf8)
        var reads = 0
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { url in
                reads += 1
                // Simulate an external save landing between the compute read
                // and the CAS re-read: the recompute must fold it in.
                if reads == 2 {
                    try "## 2026-06-07\n- [ ] existing\n- [ ] external\n"
                        .write(to: url, atomically: true, encoding: .utf8)
                }
                return try Data(contentsOf: url)
            },
            writeData: { data, url in try data.write(to: url, options: .atomic) }
        )
        try store.writeDayPlan(
            date: "2026-06-07", entries: [PlanEntry(title: "planned")], replace: false)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("- [ ] external"), "concurrent edit must survive: \(text)")
        XCTAssertTrue(text.contains("- [ ] planned"))
    }

    func testWriteDayPlanFailedWriteDoesNotSuppressNextReload() throws {
        try "## 2026-06-07\n- [ ] existing\n".write(to: file, atomically: true, encoding: .utf8)
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { try Data(contentsOf: $0) },
            writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) }
        )
        XCTAssertThrowsError(try store.writeDayPlan(
            date: "2026-06-07", entries: [PlanEntry(title: "planned")], replace: false))
        // The failed write must not have armed the reload-suppression value:
        // an external editor writing those exact bytes must still display.
        let external = "## 2026-06-07\n- [ ] existing\n- [ ] planned\n"
        try external.write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(store.todayItems.map(\.title), ["existing", "planned"])
    }

    func testAddDoesNotWriteWhenExistingFileCannotBeRead() {
        var didWrite = false
        let store = TodoStore(
            fileURL: file,
            todayProvider: { "2026-06-07" },
            readData: { _ in throw CocoaError(.fileReadNoPermission) },
            writeData: { _, _ in didWrite = true }
        )

        store.add("new task")

        XCTAssertFalse(didWrite)
        XCTAssertEqual(store.statusMessage, "Could not read drawer file")
    }
}
