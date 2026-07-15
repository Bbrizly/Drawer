import DrawerCore
import XCTest
@testable import DrawerBureau

/// R3 writeback (spec flow e): sticky edits land in Drawer.md through
/// `TodoStore.rename` / `.setNote` (content-CAS, watcher-loop suppression is
/// TodoStore's own tested contract), resolved through the receipt link so an
/// edit never writes to a task the receipt no longer represents.
@MainActor
final class StickyWritebackTests: XCTestCase {
    private var dir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("Drawer.md")
        try """
        ## 2026-07-13
        - [ ] Call the landlord
            Ask about the lease
            Mention the heater
        - [ ] Ship the release
        """.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeFeature() -> (BureauFeature, TodoStore) {
        let store = TodoStore(fileURL: fileURL, todayProvider: { "2026-07-13" })
        store.reload()
        return (BureauFeature(store: store, directory: dir), store)
    }

    private func fileText() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func queuedID(_ feature: BureauFeature, _ item: TodoItem) -> UUID {
        feature.queue(item)
        return feature.receipts.document.receipts.first { $0.textSnapshot == item.title }!.id
    }

    func testLiveItemResolvesExactTriple() {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[0])
        XCTAssertEqual(feature.liveItem(for: id)?.title, "Call the landlord")
    }

    func testLiveItemRelinksAfterExternalRenameAndRefreshesSnapshot() {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[1])
        // An external edit (Obsidian) tweaks the title under the receipt.
        store.rename(store.todayItems[1], to: "Ship the release today")
        let item = feature.liveItem(for: id)
        XCTAssertEqual(item?.title, "Ship the release today")
        XCTAssertEqual(
            feature.receipts.document.receipts.first { $0.id == id }?.textSnapshot,
            "Ship the release today"
        )
    }

    func testLiveItemOrphanExpiresTheReceipt() {
        let (feature, _) = makeFeature()
        let link = ReceiptLink(textSnapshot: "Completely unrelated zebra parade", sectionDate: "2026-07-13")
        feature.receipts.add(link)
        XCTAssertNil(feature.liveItem(for: link.id))
        XCTAssertEqual(
            feature.receipts.document.receipts.first { $0.id == link.id }?.state,
            .expired
        )
    }

    func testRenameStickyWritesThroughToFile() throws {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[0])
        feature.renameSticky(id, to: "Call the mayor")
        XCTAssertTrue(try fileText().contains("- [ ] Call the mayor"))
        XCTAssertFalse(try fileText().contains("Call the landlord"))
        // The note lines stayed with the renamed task.
        XCTAssertTrue(try fileText().contains("    Ask about the lease"))
        XCTAssertEqual(
            feature.receipts.document.receipts.first { $0.id == id }?.textSnapshot,
            "Call the mayor"
        )
    }

    func testRenameStickyIgnoresEmptyTitle() throws {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[0])
        feature.renameSticky(id, to: "   ")
        XCTAssertTrue(try fileText().contains("- [ ] Call the landlord"))
    }

    func testSubtasksReadTheNoteLines() {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[0])
        XCTAssertEqual(feature.subtasks(for: id), ["Ask about the lease", "Mention the heater"])
    }

    func testSubtasksAreEmptyForNotelessTask() {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[1])
        XCTAssertEqual(feature.subtasks(for: id), [])
    }

    func testSetSubtasksWritesNoteLinesAndRoundTrips() throws {
        let (feature, store) = makeFeature()
        let id = queuedID(feature, store.todayItems[1])
        feature.setSubtasks(id, ["Tag the build", "  ", "Write the notes"])
        XCTAssertTrue(try fileText().contains("- [ ] Ship the release\n    Tag the build\n    Write the notes"))
        XCTAssertEqual(feature.subtasks(for: id), ["Tag the build", "Write the notes"])
    }
}

/// The `StickyModel` edit surface is pure and display-free.
@MainActor
final class StickyModelEditTests: XCTestCase {
    private func makeModel(subtasks: [String] = [], cap: Int = 3) -> StickyModel {
        let model = StickyModel(receiptID: UUID(), title: "Call the landlord", size: .full)
        model.subtasks = subtasks
        model.subtaskVisibleCap = cap
        return model
    }

    func testCommitTitleTrimsAndNotifies() {
        let model = makeModel()
        var committed: [String] = []
        model.onCommitTitle = { committed.append($0) }
        model.title = "  Call the mayor  "
        model.commitTitle()
        XCTAssertEqual(model.title, "Call the mayor")
        XCTAssertEqual(committed, ["Call the mayor"])
    }

    func testCommitEmptyTitleRevertsWithoutNotifying() {
        let model = makeModel()
        var committed: [String] = []
        model.onCommitTitle = { committed.append($0) }
        model.title = "   "
        model.commitTitle()
        XCTAssertEqual(model.title, "Call the landlord")
        XCTAssertTrue(committed.isEmpty)
    }

    func testCommitSubtasksDropsEmptiedRows() {
        let model = makeModel(subtasks: ["a", "  ", "b"])
        var committed: [[String]] = []
        model.onCommitSubtasks = { committed.append($0) }
        model.commitSubtasks()
        XCTAssertEqual(model.subtasks, ["a", "b"])
        XCTAssertEqual(committed, [["a", "b"]])
    }

    func testVisibleCountCapsUntilExpanded() {
        let model = makeModel(subtasks: ["a", "b", "c", "d", "e"], cap: 3)
        XCTAssertEqual(model.visibleSubtaskCount, 3)
        XCTAssertEqual(model.overflowCount, 2)
        model.expand()
        XCTAssertEqual(model.visibleSubtaskCount, 5)
        XCTAssertEqual(model.overflowCount, 0)
    }

    func testCycleSizeCollapsesExpansionAndHidesSubtasks() {
        let model = makeModel(subtasks: ["a", "b", "c", "d"], cap: 3)
        model.expand()
        model.cycleSize()
        XCTAssertEqual(model.size, .title)
        XCTAssertFalse(model.isExpanded)
        XCTAssertEqual(model.visibleSubtaskCount, 0)
    }

    func testAddSubtaskAppendsTrimmedAndSkipsEmpty() {
        let model = makeModel(subtasks: ["a"])
        var committed: [[String]] = []
        model.onCommitSubtasks = { committed.append($0) }
        model.addSubtask("  b  ")
        model.addSubtask("   ")
        XCTAssertEqual(model.subtasks, ["a", "b"])
        XCTAssertEqual(committed, [["a", "b"]])
    }
}
