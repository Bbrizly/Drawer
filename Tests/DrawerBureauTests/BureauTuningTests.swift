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
        XCTAssertEqual(d.version, 2)
        XCTAssertEqual(d.transition.pushMs, 320)
        XCTAssertEqual(d.transition.easing, [0.16, 1.0, 0.3, 1.0])
        // Top-down drawer: no gravity, so receipts do not fall to the bottom.
        XCTAssertEqual(d.physics.gravity, 0)
        XCTAssertEqual(d.rustle.rateCapMs, 250)
        XCTAssertEqual(d.print.stepMs, 55)
        XCTAssertEqual(d.print.queueStaggerMs, 250)
        XCTAssertEqual(d.stamp.slamFrames, 12)
        XCTAssertEqual(d.stamp.inkRotationMinDeg, 2)
        XCTAssertEqual(d.stamp.inkRotationMaxDeg, 4)
        XCTAssertEqual(d.crumple.frames, 8)
        XCTAssertEqual(d.hoverScroll.inertiaFriction, 0.92)
        XCTAssertEqual(d.sticky.liveCap, 12)
        XCTAssertEqual(d.sticky.subtaskVisibleCap, 6)
        XCTAssertEqual(d.sticky.pullOutScale, 1.5)
        XCTAssertTrue(d.texture.rerenderOnEditOnly)
        XCTAssertTrue(d.filedTray.clearsMonday)
    }

    /// A version-1 file on disk (old gravity, no pullOutScale) is stale: the
    /// values changed meaning at version 2, so it must load as the new defaults
    /// and be rewritten so the old gravity never survives.
    func testVersion1FileMigratesToDefaultsAndRewrites() throws {
        let v1 = """
        {
          "version": 1,
          "transition": { "pushMs": 320, "easing": [0.16, 1.0, 0.3, 1.0], "reduceMotionCrossfadeMs": 160 },
          "physics": { "repulsionRadius": 90, "repulsionStrength": 12, "torque": 0.4, "friction": 0.7, "restitution": 0.15, "linearDamping": 3.0, "angularDamping": 4.0, "gravity": -3.0 },
          "rustle": { "gain": 0.6, "velocityThreshold": 0.35, "maxVolume": 0.5, "rateCapMs": 60 },
          "print": { "stepMs": 55, "stepPx": 6, "chatterVolume": 0.4, "dingVolume": 0.7, "tearMs": 180, "dropImpulse": 8, "queueStaggerMs": 250 },
          "stamp": { "armInMs": 140, "overshootPx": 18, "settleMs": 120, "shiverPx": 3, "shiverCount": 3, "slamFrames": 12, "inkRotationMinDeg": 2, "inkRotationMaxDeg": 4, "doubleStrikeOffsetPx": 1.5, "thunkVolume": 0.8, "hapticEnabled": true },
          "crumple": { "frames": 8, "flyToTrayMs": 260 },
          "hoverScroll": { "sensitivity": 1.0, "inertiaFriction": 0.92, "minDelta": 0.5, "maxVelocity": 40 },
          "sticky": { "liveCap": 12, "subtaskVisibleCap": 6 },
          "texture": { "rerenderOnEditOnly": true },
          "filedTray": { "clearsMonday": true }
        }
        """
        try Data(v1.utf8).write(to: dir.appendingPathComponent("bureau-tuning.json"))

        let tuning = BureauTuning(directory: dir)
        XCTAssertEqual(tuning.document, BureauTuningDocument.defaults)
        XCTAssertEqual(tuning.document.version, 2)
        XCTAssertEqual(tuning.document.physics.gravity, 0)

        // The stale file was replaced on disk: a fresh load reads version 2.
        let reloaded = BureauTuning(directory: dir)
        XCTAssertEqual(reloaded.document.version, 2)
        XCTAssertEqual(reloaded.document.physics.gravity, 0)
    }
}
