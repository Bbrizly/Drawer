import XCTest
@testable import DrawerCore

final class FileWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDetectsAtomicReplace() throws {
        let file = dir.appendingPathComponent("t.md")
        try "a".write(to: file, atomically: true, encoding: .utf8)

        let watcher = FileWatcher(directory: dir)
        let exp = expectation(description: "change detected")
        exp.assertForOverFulfill = false
        watcher.onChange = { exp.fulfill() }
        watcher.start()

        // .atomic writes a temp file and renames over the target,
        // exactly what Obsidian and iCloud do.
        try "b".write(to: file, atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 3.0)
        watcher.stop()
    }

    func testRetriesUntilDirectoryExists() throws {
        // Directory doesn't exist yet (e.g. iCloud not mounted at login).
        let missing = dir.appendingPathComponent("not-yet-created")
        let watcher = FileWatcher(directory: missing, retryInterval: 0.1)
        let exp = expectation(description: "attached after retry")
        exp.assertForOverFulfill = false
        watcher.onChange = { exp.fulfill() }
        watcher.start()

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)

        wait(for: [exp], timeout: 3.0)
        watcher.stop()
    }

    func testDetectsFileCreation() throws {
        let watcher = FileWatcher(directory: dir)
        let exp = expectation(description: "creation detected")
        exp.assertForOverFulfill = false
        watcher.onChange = { exp.fulfill() }
        watcher.start()

        try "new".write(to: dir.appendingPathComponent("created.md"),
                        atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 3.0)
        watcher.stop()
    }
}
