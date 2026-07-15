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
        XCTAssertEqual(d.version, 5)
        XCTAssertEqual(d.transition.pushMs, 320)
        XCTAssertEqual(d.transition.easing, [0.16, 1.0, 0.3, 1.0])
        // Top-down drawer: no gravity, so receipts do not fall to the bottom.
        XCTAssertEqual(d.physics.gravity, 0)
        XCTAssertEqual(d.physics.pushScale, 0.02)
        XCTAssertEqual(d.physics.torqueScale, 0.001)
        XCTAssertTrue(d.physics.rotationEnabled)
        XCTAssertEqual(d.physics.maxTiltDeg, 180)
        XCTAssertTrue(d.physics.papersCollide)
        XCTAssertEqual(d.rustle.rateCapMs, 250)
        XCTAssertEqual(d.rustle.speedRef, 200)
        XCTAssertEqual(d.print.stepMs, 55)
        XCTAssertEqual(d.print.queueStaggerMs, 250)
        // v5 art pass: gentle spawn, big stamps.
        XCTAssertEqual(d.print.spreadDeg, 40)
        XCTAssertEqual(d.print.spin, 0.08)
        XCTAssertEqual(d.print.dropImpulse, 3)
        XCTAssertEqual(d.stamp.rackWidthPx, 280)
        XCTAssertEqual(d.stamp.stampSizePx, 96)
        XCTAssertEqual(d.stamp.tabWidthPx, 30)
        XCTAssertEqual(d.stamp.rackHeightPx, 170)
        XCTAssertEqual(d.stamp.pressMs, 90)
        XCTAssertEqual(d.stamp.slideVolume, 0.5)
        XCTAssertEqual(d.stamp.inkRotationMinDeg, 2)
        XCTAssertEqual(d.stamp.inkRotationMaxDeg, 4)
        XCTAssertEqual(d.crumple.frames, 8)
        XCTAssertEqual(d.hoverScroll.inertiaFriction, 0.92)
        XCTAssertEqual(d.sticky.liveCap, 12)
        XCTAssertEqual(d.sticky.subtaskVisibleCap, 6)
        XCTAssertEqual(d.sticky.pullOutScale, 1.5)
        XCTAssertEqual(d.sticky.slipWidth, 96)
        XCTAssertEqual(d.sticky.slipHeight, 144)
        XCTAssertEqual(d.sticky.settleDebounceMs, 350)
        XCTAssertEqual(d.drawer.trayScale, 0.45)
        XCTAssertEqual(d.drawer.trayVisibleCap, 8)
        XCTAssertEqual(d.returnDrop.impulse, 2)
        XCTAssertEqual(d.shredder.volume, 0.7)
        XCTAssertEqual(d.shredder.widthPx, 56)
        XCTAssertEqual(d.shredder.overlayWidthPx, 170)
        XCTAssertEqual(d.shredder.overlayHeightPx, 72)
        // v5: the shredder ships off and the stub line is gone.
        XCTAssertFalse(d.shredder.enabled)
        XCTAssertTrue(d.texture.rerenderOnEditOnly)
        XCTAssertFalse(d.texture.showStubLine)
        XCTAssertEqual(d.texture.vignetteAlpha, 0.25)
        XCTAssertTrue(d.filedTray.clearsMonday)
        // v5 art block: the pixel look and its font.
        XCTAssertEqual(d.art.fontFamily, "Pixelify Sans")
        XCTAssertEqual(d.art.pixelScale, 2)
        XCTAssertEqual(d.art.titleFontSize, 15)
        XCTAssertEqual(d.art.detailFontSize, 8)
        XCTAssertEqual(d.art.paper, "#E3D6B8")
    }

    /// A texture block from before the Papers-Please look pass has neither
    /// showStubLine nor vignetteAlpha, so those must decode to their defaults
    /// while the existing rerenderOnEditOnly value survives untouched.
    func testTextureDecodesWithoutStubLineAndVignette() throws {
        let json = """
        { "rerenderOnEditOnly": false }
        """
        let t = try JSONDecoder().decode(
            BureauTextureTuning.self, from: Data(json.utf8)
        )
        XCTAssertTrue(t.showStubLine)
        XCTAssertEqual(t.vignetteAlpha, 0.25)
        XCTAssertFalse(t.rerenderOnEditOnly)
    }

    /// A hoverScroll block from before cursorFollows has no such key, so it must
    /// decode with cursorFollows defaulting to true while the other four values
    /// survive untouched.
    func testHoverScrollDecodesWithoutCursorFollows() throws {
        let json = """
        { "sensitivity": 2.0, "inertiaFriction": 0.8, "minDelta": 1.5, "maxVelocity": 25 }
        """
        let t = try JSONDecoder().decode(
            BureauHoverScrollTuning.self, from: Data(json.utf8)
        )
        XCTAssertTrue(t.cursorFollows)
        XCTAssertEqual(t.sensitivity, 2.0)
        XCTAssertEqual(t.inertiaFriction, 0.8)
        XCTAssertEqual(t.minDelta, 1.5)
        XCTAssertEqual(t.maxVelocity, 25)
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
        XCTAssertEqual(tuning.document.version, 5)
        XCTAssertEqual(tuning.document.physics.gravity, 0)

        // The stale file was replaced on disk: a fresh load reads version 5.
        let reloaded = BureauTuning(directory: dir)
        XCTAssertEqual(reloaded.document.version, 5)
        XCTAssertEqual(reloaded.document.physics.gravity, 0)
    }

    /// A version-2 file only added fields at later versions, so it is a valid
    /// tuned file, not stale. It must migrate to the current version in one
    /// load (the chain, not one bump per launch): the user's v2 values are
    /// preserved, new fields fill with defaults, and the v5 art pass lands.
    func testVersion2FileMigratesToCurrentPreservingValues() throws {
        let v2 = """
        {
          "version": 2,
          "transition": { "pushMs": 320, "easing": [0.16, 1.0, 0.3, 1.0], "reduceMotionCrossfadeMs": 160 },
          "physics": { "repulsionRadius": 90, "repulsionStrength": 42, "torque": 0.4, "friction": 0.7, "restitution": 0.15, "linearDamping": 3.0, "angularDamping": 4.0, "gravity": 0 },
          "rustle": { "gain": 0.6, "velocityThreshold": 0.35, "maxVolume": 0.5, "rateCapMs": 250 },
          "print": { "stepMs": 55, "stepPx": 6, "chatterVolume": 0.4, "dingVolume": 0.7, "tearMs": 180, "dropImpulse": 8, "queueStaggerMs": 250 },
          "stamp": { "armInMs": 140, "overshootPx": 18, "settleMs": 120, "shiverPx": 3, "shiverCount": 3, "slamFrames": 12, "inkRotationMinDeg": 2, "inkRotationMaxDeg": 4, "doubleStrikeOffsetPx": 1.5, "thunkVolume": 0.8, "hapticEnabled": true },
          "crumple": { "frames": 8, "flyToTrayMs": 260 },
          "hoverScroll": { "sensitivity": 1.0, "inertiaFriction": 0.92, "minDelta": 0.5, "maxVelocity": 40 },
          "sticky": { "liveCap": 7, "subtaskVisibleCap": 6, "pullOutScale": 1.5 },
          "texture": { "rerenderOnEditOnly": true },
          "filedTray": { "clearsMonday": true }
        }
        """
        try Data(v2.utf8).write(to: dir.appendingPathComponent("bureau-tuning.json"))

        let tuning = BureauTuning(directory: dir)
        XCTAssertEqual(tuning.document.version, 5)
        // Preserved v2 values.
        XCTAssertEqual(tuning.document.physics.repulsionStrength, 42)
        XCTAssertEqual(tuning.document.sticky.liveCap, 7)
        XCTAssertEqual(tuning.document.sticky.pullOutScale, 1.5)
        // New fields filled with defaults.
        XCTAssertEqual(tuning.document.physics.pushScale, 0.02)
        XCTAssertEqual(tuning.document.rustle.speedRef, 200)
        XCTAssertEqual(tuning.document.sticky.slipWidth, 96)
        XCTAssertEqual(tuning.document.drawer.trayScale, 0.45)
        XCTAssertEqual(tuning.document.returnDrop.impulse, 2)
        XCTAssertEqual(tuning.document.shredder.volume, 0.7)
        XCTAssertEqual(tuning.document.shredder.overlayWidthPx, 170)
        // The v5 art pass landed on top of the chain.
        XCTAssertEqual(tuning.document.print.spin, 0.08)
        XCTAssertEqual(tuning.document.stamp.rackWidthPx, 280)
        XCTAssertEqual(tuning.document.stamp.stampSizePx, 96)
        XCTAssertFalse(tuning.document.texture.showStubLine)
        XCTAssertFalse(tuning.document.shredder.enabled)

        // Written back at version 5: a fresh load reads 5 and keeps the values.
        let reloaded = BureauTuning(directory: dir)
        XCTAssertEqual(reloaded.document.version, 5)
        XCTAssertEqual(reloaded.document.physics.repulsionStrength, 42)
        XCTAssertEqual(reloaded.document.sticky.liveCap, 7)
    }

    /// A version-3 file added the overlay/rotation/slide fields at version 4, so
    /// it is a valid tuned file. It migrates to the current version in place:
    /// the user's v3 values are preserved and the new fields default.
    func testVersion3FileMigratesToCurrentPreservingValues() throws {
        var v3 = BureauTuningDocument.defaults
        v3.version = 3
        v3.physics.repulsionStrength = 33
        v3.sticky.liveCap = 9
        // Strip the fields a real v3 file would not carry so the tolerant
        // decode has to fill them from defaults.
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(v3)
        ) as! [String: Any]
        var shredder = object["shredder"] as! [String: Any]
        shredder.removeValue(forKey: "overlayWidthPx")
        shredder.removeValue(forKey: "overlayHeightPx")
        object["shredder"] = shredder
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: dir.appendingPathComponent("bureau-tuning.json"))

        let tuning = BureauTuning(directory: dir)
        XCTAssertEqual(tuning.document.version, 5)
        // Preserved v3 values.
        XCTAssertEqual(tuning.document.physics.repulsionStrength, 33)
        XCTAssertEqual(tuning.document.sticky.liveCap, 9)
        // New fields filled with defaults.
        XCTAssertEqual(tuning.document.shredder.overlayWidthPx, 170)
        XCTAssertEqual(tuning.document.shredder.overlayHeightPx, 72)

        // Written back at version 5: a fresh load reads 5 and keeps the values.
        let reloaded = BureauTuning(directory: dir)
        XCTAssertEqual(reloaded.document.version, 5)
        XCTAssertEqual(reloaded.document.physics.repulsionStrength, 33)
    }
}
