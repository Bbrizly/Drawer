import XCTest
@testable import DrawerCore

@MainActor
final class NotesStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLoadReadsFileIntoText() throws {
        let file = dir.appendingPathComponent("notes.md")
        try "hello speech".write(to: file, atomically: true, encoding: .utf8)

        let store = NotesStore(fileURL: file)
        store.load()

        XCTAssertEqual(store.text, "hello speech")
    }

    func testLoadMissingFileGivesEmptyText() {
        let file = dir.appendingPathComponent("does-not-exist.md")
        let store = NotesStore(fileURL: file)
        store.load()
        XCTAssertEqual(store.text, "")
    }

    func testLoadDoesNotTriggerASave() {
        let file = dir.appendingPathComponent("notes.md")
        var writes = 0
        let store = NotesStore(
            fileURL: file,
            debounce: 0,
            readString: { _ in "from disk" },
            writeString: { _, _ in writes += 1 }
        )
        store.load()
        XCTAssertEqual(store.text, "from disk")
        XCTAssertEqual(writes, 0, "loading must not write back")
    }

    func testSaveNowWritesCurrentTextImmediately() throws {
        let file = dir.appendingPathComponent("notes.md")
        let store = NotesStore(fileURL: file)
        store.text = "draft line"
        store.saveNow()
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(onDisk, "draft line")
    }

    func testEditWritesAfterDebounce() throws {
        let file = dir.appendingPathComponent("notes.md")
        var lastWritten: String?
        let store = NotesStore(
            fileURL: file,
            debounce: 0.05,
            readString: { try String(contentsOf: $0, encoding: .utf8) },
            writeString: { value, _ in lastWritten = value }
        )
        store.text = "typed"

        let exp = expectation(description: "debounced write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(lastWritten, "typed")
    }

    func testRapidEditsCollapseToOneWrite() throws {
        let file = dir.appendingPathComponent("notes.md")
        var writes = 0
        let store = NotesStore(
            fileURL: file,
            debounce: 0.05,
            readString: { try String(contentsOf: $0, encoding: .utf8) },
            writeString: { _, _ in writes += 1 }
        )
        store.text = "a"
        store.text = "ab"
        store.text = "abc"

        let exp = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(writes, 1, "debounce should collapse rapid edits")
    }
}
