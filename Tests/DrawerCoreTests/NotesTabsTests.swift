import XCTest

@testable import DrawerCore

/// Tabs are files in a folder, so these run against a real temp directory:
/// the listing, the move-aside on close, and the "nothing is ever deleted"
/// promise are all filesystem behaviour.
@MainActor
final class NotesTabsTests: XCTestCase {
    private var dir: URL!
    private var primary: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        primary = dir.appendingPathComponent("Notes.md")
        try "first note".write(to: primary, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func store() -> NotesStore {
        let s = NotesStore(fileURL: primary, debounce: 0)
        s.load()
        return s
    }

    func testStartsWithOneTab() {
        let s = store()
        XCTAssertEqual(s.tabs.count, 1)
        XCTAssertEqual(s.activeIndex, 0)
        XCTAssertEqual(s.text, "first note")
    }

    func testAddTabOpensAnEmptyFile() {
        let s = store()
        s.addTab()
        XCTAssertEqual(s.tabs.count, 2)
        XCTAssertEqual(s.activeIndex, 1)
        XCTAssertEqual(s.text, "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.fileURL.path))
        XCTAssertEqual(s.fileURL.deletingLastPathComponent(), s.tabsDirectory)
    }

    func testSwitchingTabsKeepsBothTexts() {
        let s = store()
        s.addTab()
        s.text = "second note"
        s.saveNow()
        s.select(0)
        XCTAssertEqual(s.text, "first note")
        s.select(1)
        XCTAssertEqual(s.text, "second note")
    }

    func testTabLabelFollowsTheFirstLine() {
        let s = store()
        s.addTab()
        s.text = "Shipping plan\nrest of it"
        s.saveNow()
        XCTAssertEqual(s.tabs[1].label, "Shipping plan")
    }

    func testLabelFallsBackToTheFileName() {
        XCTAssertEqual(NotesStore.label(for: "   \n\n", fallback: "Note 2"), "Note 2")
        XCTAssertEqual(NotesStore.label(for: "# Heading", fallback: "Note 2"), "Heading")
    }

    func testCloseKeepsTheFileOnDisk() {
        let s = store()
        s.addTab()
        s.text = "keep me"
        s.saveNow()
        let closed = s.fileURL

        s.removeTab(at: 1)

        XCTAssertEqual(s.tabs.count, 1)
        XCTAssertEqual(s.text, "first note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: closed.path))
        let kept = s.removedDirectory.appendingPathComponent(closed.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "keep me")
    }

    func testClosingOneTabDoesNotLoseAnotherTabsEdits() {
        let s = store()
        s.addTab()          // tab 1
        s.text = "kept"
        s.saveNow()
        s.addTab()          // tab 2
        s.text = "doomed"
        s.saveNow()
        s.select(1)
        s.text = "kept, edited"   // still inside the debounce
        s.removeTab(at: 2)
        XCTAssertEqual(s.text, "kept, edited")
        XCTAssertEqual(s.activeIndex, 1)
    }

    func testFirstTabCannotBeClosed() {
        let s = store()
        s.removeTab(at: 0)
        XCTAssertEqual(s.tabs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path))
    }

    func testTabsAreFoundAgainOnNextLaunch() throws {
        let first = store()
        first.addTab()
        first.text = "later"
        first.saveNow()

        let second = store()
        XCTAssertEqual(second.tabs.count, 2)
        XCTAssertEqual(second.activeIndex, 0)
        second.select(1)
        XCTAssertEqual(second.text, "later")
    }
}
