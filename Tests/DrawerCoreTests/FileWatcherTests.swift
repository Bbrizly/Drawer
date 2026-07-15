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

    func testPollFallbackDetectsChangeWhenDirectoryIsUnopenable() throws {
        // The sandboxed App Store build can read a user-picked file but not
        // open its parent directory; the watcher falls back to polling mtime.
        // Simulate by watching a directory that never exists while pollFile
        // points at a real file.
        let file = dir.appendingPathComponent("t.md")
        try "a".write(to: file, atomically: true, encoding: .utf8)

        let unopenable = dir.appendingPathComponent("never-created")
        let watcher = FileWatcher(directory: unopenable, retryInterval: 60, pollFile: file)
        let exp = expectation(description: "poll detected the change")
        exp.assertForOverFulfill = false
        watcher.onChange = { exp.fulfill() }
        watcher.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? "changed content".write(to: file, atomically: true, encoding: .utf8)
        }

        wait(for: [exp], timeout: 8.0)  // poll cadence is 2s
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
