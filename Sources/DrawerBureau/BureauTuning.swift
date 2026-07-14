import DrawerCore
import Foundation

/// Transition timing for entering/leaving Bureau mode (spec "Layout and mode
/// switch"). `easing` is a 4-value cubic-bezier control-point array
/// (x1, y1, x2, y2), matched to how CSS/`CAMediaTimingFunction` expresses one.
public struct BureauTransitionTuning: Codable, Equatable, Sendable {
    public var pushMs: Double
    public var easing: [Double]
    public var reduceMotionCrossfadeMs: Double

    public init(pushMs: Double, easing: [Double], reduceMotionCrossfadeMs: Double) {
        self.pushMs = pushMs
        self.easing = easing
        self.reduceMotionCrossfadeMs = reduceMotionCrossfadeMs
    }
}

/// SpriteKit body feel for the rummage scene (spec "The drawer scene").
public struct BureauPhysicsTuning: Codable, Equatable, Sendable {
    public var repulsionRadius: Double
    public var repulsionStrength: Double
    public var torque: Double
    public var friction: Double
    public var restitution: Double
    public var linearDamping: Double
    public var angularDamping: Double
    public var gravity: Double

    public init(
        repulsionRadius: Double, repulsionStrength: Double, torque: Double, friction: Double,
        restitution: Double, linearDamping: Double, angularDamping: Double, gravity: Double
    ) {
        self.repulsionRadius = repulsionRadius
        self.repulsionStrength = repulsionStrength
        self.torque = torque
        self.friction = friction
        self.restitution = restitution
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravity = gravity
    }
}

/// Paper-rustle sound driven by receipt velocity as the cursor rummages.
public struct BureauRustleTuning: Codable, Equatable, Sendable {
    public var gain: Double
    public var velocityThreshold: Double
    public var maxVolume: Double
    public var rateCapMs: Double

    public init(gain: Double, velocityThreshold: Double, maxVolume: Double, rateCapMs: Double) {
        self.gain = gain
        self.velocityThreshold = velocityThreshold
        self.maxVolume = maxVolume
        self.rateCapMs = rateCapMs
    }
}

/// Thermal-printer emergence for print-on-add (spec "The printer").
public struct BureauPrintTuning: Codable, Equatable, Sendable {
    public var stepMs: Double
    public var stepPx: Double
    public var chatterVolume: Double
    public var dingVolume: Double
    public var tearMs: Double
    public var dropImpulse: Double
    public var queueStaggerMs: Double

    public init(
        stepMs: Double, stepPx: Double, chatterVolume: Double, dingVolume: Double,
        tearMs: Double, dropImpulse: Double, queueStaggerMs: Double
    ) {
        self.stepMs = stepMs
        self.stepPx = stepPx
        self.chatterVolume = chatterVolume
        self.dingVolume = dingVolume
        self.tearMs = tearMs
        self.dropImpulse = dropImpulse
        self.queueStaggerMs = queueStaggerMs
    }
}

/// The stamp arm's four keyframes plus ink/haptic feel (spec "The stamp").
public struct BureauStampTuning: Codable, Equatable, Sendable {
    public var armInMs: Double
    public var overshootPx: Double
    public var settleMs: Double
    public var shiverPx: Double
    public var shiverCount: Int
    public var slamFrames: Int
    public var inkRotationMinDeg: Double
    public var inkRotationMaxDeg: Double
    public var doubleStrikeOffsetPx: Double
    public var thunkVolume: Double
    public var hapticEnabled: Bool

    public init(
        armInMs: Double, overshootPx: Double, settleMs: Double, shiverPx: Double,
        shiverCount: Int, slamFrames: Int, inkRotationMinDeg: Double, inkRotationMaxDeg: Double,
        doubleStrikeOffsetPx: Double, thunkVolume: Double, hapticEnabled: Bool
    ) {
        self.armInMs = armInMs
        self.overshootPx = overshootPx
        self.settleMs = settleMs
        self.shiverPx = shiverPx
        self.shiverCount = shiverCount
        self.slamFrames = slamFrames
        self.inkRotationMinDeg = inkRotationMinDeg
        self.inkRotationMaxDeg = inkRotationMaxDeg
        self.doubleStrikeOffsetPx = doubleStrikeOffsetPx
        self.thunkVolume = thunkVolume
        self.hapticEnabled = hapticEnabled
    }
}

/// DONE's receipt crumple before it flies to the FILED tray.
public struct BureauCrumpleTuning: Codable, Equatable, Sendable {
    public var frames: Int
    public var flyToTrayMs: Double

    public init(frames: Int, flyToTrayMs: Double) {
        self.frames = frames
        self.flyToTrayMs = flyToTrayMs
    }
}

/// Two-finger scroll-to-move a sticky (spec Decision 2).
public struct BureauHoverScrollTuning: Codable, Equatable, Sendable {
    public var sensitivity: Double
    public var inertiaFriction: Double
    public var minDelta: Double
    public var maxVelocity: Double

    public init(sensitivity: Double, inertiaFriction: Double, minDelta: Double, maxVelocity: Double) {
        self.sensitivity = sensitivity
        self.inertiaFriction = inertiaFriction
        self.minDelta = minDelta
        self.maxVelocity = maxVelocity
    }
}

/// Sticky panel caps (spec "Pull-out").
public struct BureauStickyTuning: Codable, Equatable, Sendable {
    public var liveCap: Int
    public var subtaskVisibleCap: Int

    public init(liveCap: Int, subtaskVisibleCap: Int) {
        self.liveCap = liveCap
        self.subtaskVisibleCap = subtaskVisibleCap
    }
}

/// `TextureRenderer` re-render policy (spec risk #6).
public struct BureauTextureTuning: Codable, Equatable, Sendable {
    public var rerenderOnEditOnly: Bool

    public init(rerenderOnEditOnly: Bool) {
        self.rerenderOnEditOnly = rerenderOnEditOnly
    }
}

/// FILED tray clearing ceremony (spec Decision 4).
public struct BureauFiledTrayTuning: Codable, Equatable, Sendable {
    public var clearsMonday: Bool

    public init(clearsMonday: Bool) {
        self.clearsMonday = clearsMonday
    }
}

/// The full contents of `bureau-tuning.json`: every feel value in one place,
/// schema per `bureau-impl.md` section 5.
public struct BureauTuningDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var transition: BureauTransitionTuning
    public var physics: BureauPhysicsTuning
    public var rustle: BureauRustleTuning
    public var print: BureauPrintTuning
    public var stamp: BureauStampTuning
    public var crumple: BureauCrumpleTuning
    public var hoverScroll: BureauHoverScrollTuning
    public var sticky: BureauStickyTuning
    public var texture: BureauTextureTuning
    public var filedTray: BureauFiledTrayTuning

    public init(
        version: Int, transition: BureauTransitionTuning, physics: BureauPhysicsTuning,
        rustle: BureauRustleTuning, print: BureauPrintTuning, stamp: BureauStampTuning,
        crumple: BureauCrumpleTuning, hoverScroll: BureauHoverScrollTuning,
        sticky: BureauStickyTuning, texture: BureauTextureTuning, filedTray: BureauFiledTrayTuning
    ) {
        self.version = version
        self.transition = transition
        self.physics = physics
        self.rustle = rustle
        self.print = print
        self.stamp = stamp
        self.crumple = crumple
        self.hoverScroll = hoverScroll
        self.sticky = sticky
        self.texture = texture
        self.filedTray = filedTray
    }

    /// The values in `bureau-impl.md` section 5, written to disk the first
    /// time the app looks for the tuning file.
    public static let defaults = BureauTuningDocument(
        version: 1,
        transition: BureauTransitionTuning(
            pushMs: 320, easing: [0.16, 1.0, 0.3, 1.0], reduceMotionCrossfadeMs: 160
        ),
        physics: BureauPhysicsTuning(
            repulsionRadius: 90, repulsionStrength: 12, torque: 0.4, friction: 0.7,
            restitution: 0.15, linearDamping: 3.0, angularDamping: 4.0, gravity: -3.0
        ),
        rustle: BureauRustleTuning(
            gain: 0.6, velocityThreshold: 0.35, maxVolume: 0.5, rateCapMs: 60
        ),
        print: BureauPrintTuning(
            stepMs: 55, stepPx: 6, chatterVolume: 0.4, dingVolume: 0.7,
            tearMs: 180, dropImpulse: 8, queueStaggerMs: 250
        ),
        stamp: BureauStampTuning(
            armInMs: 140, overshootPx: 18, settleMs: 120, shiverPx: 3,
            shiverCount: 3, slamFrames: 12, inkRotationMinDeg: 2, inkRotationMaxDeg: 4,
            doubleStrikeOffsetPx: 1.5, thunkVolume: 0.8, hapticEnabled: true
        ),
        crumple: BureauCrumpleTuning(frames: 8, flyToTrayMs: 260),
        hoverScroll: BureauHoverScrollTuning(
            sensitivity: 1.0, inertiaFriction: 0.92, minDelta: 0.5, maxVelocity: 40
        ),
        sticky: BureauStickyTuning(liveCap: 12, subtaskVisibleCap: 6),
        texture: BureauTextureTuning(rerenderOnEditOnly: true),
        filedTray: BureauFiledTrayTuning(clearsMonday: true)
    )
}

/// Loads `bureau-tuning.json` and hot-reloads it when the file changes on
/// disk, so the (future, R5) slider panel can write live edits and every
/// reader picks them up through the same `@Published` document. Modeled on
/// `BoardStore`/`ReceiptStore`: IO injected for tests, directory threaded in
/// as a `URL` for the same reason `ReceiptStore` takes one (see its type doc;
/// `AppPaths` lives in the `Drawer` target, which depends on `DrawerBureau`).
///
/// Do NOT build the slider panel UI here; this is R5. This type only owns the
/// data and the reload plumbing the panel will bind to.
@MainActor
public final class BureauTuning: ObservableObject {
    @Published public private(set) var document: BureauTuningDocument

    public let directory: URL
    public var tuningFile: URL { directory.appendingPathComponent("bureau-tuning.json") }

    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void
    private var watcher: FileWatcher?

    public convenience init(directory: URL) {
        self.init(
            directory: directory,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            }
        )
    }

    init(
        directory: URL,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void
    ) {
        self.directory = directory
        self.readData = readData
        self.writeData = writeData
        self.document = BureauTuningDocument.defaults
        load()
    }

    /// Reads bureau-tuning.json into memory, writing the defaults file first
    /// if it is missing so there is always something on disk for a hand edit
    /// or the (future) slider panel to find and change.
    public func load() {
        if (try? readData(tuningFile)) == nil {
            write(BureauTuningDocument.defaults)
        }
        guard let data = try? readData(tuningFile),
              let doc = try? Self.decoder.decode(BureauTuningDocument.self, from: data)
        else {
            document = BureauTuningDocument.defaults
            return
        }
        document = doc
    }

    /// Watches the data directory and reloads whenever bureau-tuning.json
    /// changes underneath the app (a hand edit, or later the slider panel's
    /// own write). Call once; safe to call again after `stopWatching`.
    // ponytail: FileWatcher only watches whole directories, so any sibling
    // file churn (e.g. ReceiptStore autosaving next door) also triggers a
    // reload here; harmless since `load()` is cheap and idempotent, but if
    // the directory gets busy, give tuning its own subdirectory.
    public func startWatching() {
        stopWatching()
        let watcher = FileWatcher(directory: directory)
        watcher.onChange = { [weak self] in self?.load() }
        watcher.start()
        self.watcher = watcher
    }

    public func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    /// A live edit from the tuning panel (R5): publish it and write it to the
    /// json, so a hand edit and a slider drag are the same one path.
    public func update(_ doc: BureauTuningDocument) {
        document = doc
        write(doc)
    }

    private func write(_ doc: BureauTuningDocument) {
        guard let data = try? Self.encoder.encode(doc) else { return }
        try? writeData(data, tuningFile)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()
}
