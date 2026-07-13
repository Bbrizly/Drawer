import XCTest
@testable import DrawerBureau

@MainActor
final class BureauTuningTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testInitWritesDefaultsFileWhenMissing() {
        let tuning = BureauTuning(directory: dir)
        XCTAssertEqual(tuning.document, BureauTuningDocument.defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tuning.tuningFile.path))
    }

    func testMalformedFileFallsBackToDefaults() throws {
        try Data("not json".utf8).write(to: dir.appendingPathComponent("bureau-tuning.json"))
        let tuning = BureauTuning(directory: dir)
        XCTAssertEqual(tuning.document, BureauTuningDocument.defaults)
    }

    func testLoadPicksUpAManualEdit() throws {
        let tuning = BureauTuning(directory: dir)
        var doc = BureauTuningDocument.defaults
        doc.physics.repulsionStrength = 42
        doc.stamp.hapticEnabled = false
        try JSONEncoder().encode(doc).write(to: tuning.tuningFile, options: .atomic)

        tuning.load()

        XCTAssertEqual(tuning.document.physics.repulsionStrength, 42)
        XCTAssertFalse(tuning.document.stamp.hapticEnabled)
    }

    /// The real hot-reload path: a change lands on disk (the future slider
    /// panel, or a hand edit) and the FileWatcher notices without anyone
    /// calling `load()` directly. Same temp-dir/expectation shape as
    /// `FileWatcherTests.testDetectsAtomicReplace`.
    func testHotReloadPicksUpAnEditedFileOnDisk() throws {
        let tuning = BureauTuning(directory: dir)
        tuning.startWatching()
        defer { tuning.stopWatching() }

        var doc = BureauTuningDocument.defaults
        doc.physics.repulsionStrength = 42
        doc.stamp.hapticEnabled = false
        try JSONEncoder().encode(doc).write(to: tuning.tuningFile, options: .atomic)

        let exp = expectation(description: "tuning file change observed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exp.fulfill() }
        wait(for: [exp], timeout: 3.0)

        XCTAssertEqual(tuning.document.physics.repulsionStrength, 42)
        XCTAssertFalse(tuning.document.stamp.hapticEnabled)
    }

    func testDefaultsMatchTheSchemaInBureauImplDoc() {
        let d = BureauTuningDocument.defaults
        XCTAssertEqual(d.version, 1)
        XCTAssertEqual(d.transition.pushMs, 320)
        XCTAssertEqual(d.transition.easing, [0.16, 1.0, 0.3, 1.0])
        XCTAssertEqual(d.physics.gravity, -3.0)
        XCTAssertEqual(d.print.stepMs, 55)
        XCTAssertEqual(d.print.queueStaggerMs, 250)
        XCTAssertEqual(d.stamp.slamFrames, 12)
        XCTAssertEqual(d.stamp.inkRotationMinDeg, 2)
        XCTAssertEqual(d.stamp.inkRotationMaxDeg, 4)
        XCTAssertEqual(d.crumple.frames, 8)
        XCTAssertEqual(d.hoverScroll.inertiaFriction, 0.92)
        XCTAssertEqual(d.sticky.liveCap, 12)
        XCTAssertEqual(d.sticky.subtaskVisibleCap, 6)
        XCTAssertTrue(d.texture.rerenderOnEditOnly)
        XCTAssertTrue(d.filedTray.clearsMonday)
    }
}
