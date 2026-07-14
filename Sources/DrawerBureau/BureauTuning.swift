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
    /// Scales the per-tick rummage push impulse (was a hardcoded 0.02).
    public var pushScale: Double
    /// Scales the per-tick rummage twist impulse (was a hardcoded 0.001).
    public var torqueScale: Double
    /// Whether a slip may spin at all (`body.allowsRotation`). Off pins every
    /// slip upright while still letting it slide.
    public var rotationEnabled: Bool
    /// How far (degrees) a slip may tilt from upright. 180 means unlimited; 0
    /// keeps papers dead upright. Enforced per frame so a slider edit applies
    /// live.
    public var maxTiltDeg: Double
    /// Whether slips collide with each other. Off lets them slide over one
    /// another; they always still collide with the drawer walls.
    public var papersCollide: Bool

    public init(
        repulsionRadius: Double, repulsionStrength: Double, torque: Double, friction: Double,
        restitution: Double, linearDamping: Double, angularDamping: Double, gravity: Double,
        pushScale: Double, torqueScale: Double,
        rotationEnabled: Bool, maxTiltDeg: Double, papersCollide: Bool
    ) {
        self.repulsionRadius = repulsionRadius
        self.repulsionStrength = repulsionStrength
        self.torque = torque
        self.friction = friction
        self.restitution = restitution
        self.linearDamping = linearDamping
        self.angularDamping = angularDamping
        self.gravity = gravity
        self.pushScale = pushScale
        self.torqueScale = torqueScale
        self.rotationEnabled = rotationEnabled
        self.maxTiltDeg = maxTiltDeg
        self.papersCollide = papersCollide
    }

    // Version-2 files predate pushScale/torqueScale and version-3 files predate
    // the rotation controls; decode them all tolerantly so the migration can
    // fill the new fields without discarding tuned values. The defaults keep
    // today's behavior (free spin, no tilt limit, papers collide).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repulsionRadius = try c.decode(Double.self, forKey: .repulsionRadius)
        repulsionStrength = try c.decode(Double.self, forKey: .repulsionStrength)
        torque = try c.decode(Double.self, forKey: .torque)
        friction = try c.decode(Double.self, forKey: .friction)
        restitution = try c.decode(Double.self, forKey: .restitution)
        linearDamping = try c.decode(Double.self, forKey: .linearDamping)
        angularDamping = try c.decode(Double.self, forKey: .angularDamping)
        gravity = try c.decode(Double.self, forKey: .gravity)
        pushScale = try c.decodeIfPresent(Double.self, forKey: .pushScale) ?? 0.02
        torqueScale = try c.decodeIfPresent(Double.self, forKey: .torqueScale) ?? 0.001
        rotationEnabled = try c.decodeIfPresent(Bool.self, forKey: .rotationEnabled) ?? true
        maxTiltDeg = try c.decodeIfPresent(Double.self, forKey: .maxTiltDeg) ?? 180
        papersCollide = try c.decodeIfPresent(Bool.self, forKey: .papersCollide) ?? true
    }
}

/// Paper-rustle sound driven by receipt velocity as the cursor rummages.
public struct BureauRustleTuning: Codable, Equatable, Sendable {
    public var gain: Double
    public var velocityThreshold: Double
    public var maxVolume: Double
    public var rateCapMs: Double
    /// The body speed (points/sec) mapped to full rustle intensity in
    /// `BureauScene.update` (was a hardcoded 200).
    public var speedRef: Double

    public init(
        gain: Double, velocityThreshold: Double, maxVolume: Double, rateCapMs: Double,
        speedRef: Double
    ) {
        self.gain = gain
        self.velocityThreshold = velocityThreshold
        self.maxVolume = maxVolume
        self.rateCapMs = rateCapMs
        self.speedRef = speedRef
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gain = try c.decode(Double.self, forKey: .gain)
        velocityThreshold = try c.decode(Double.self, forKey: .velocityThreshold)
        maxVolume = try c.decode(Double.self, forKey: .maxVolume)
        rateCapMs = try c.decode(Double.self, forKey: .rateCapMs)
        speedRef = try c.decodeIfPresent(Double.self, forKey: .speedRef) ?? 200
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
    /// Half-angle (degrees) of the fresh-print fling spread (was hardcoded 70).
    public var spreadDeg: Double
    /// Random +/- fraction on the fling magnitude (was hardcoded 0.3).
    public var impulseVariance: Double
    /// Half-range of the fresh-print angular impulse (was hardcoded 0.15).
    public var spin: Double

    public init(
        stepMs: Double, stepPx: Double, chatterVolume: Double, dingVolume: Double,
        tearMs: Double, dropImpulse: Double, queueStaggerMs: Double,
        spreadDeg: Double, impulseVariance: Double, spin: Double
    ) {
        self.stepMs = stepMs
        self.stepPx = stepPx
        self.chatterVolume = chatterVolume
        self.dingVolume = dingVolume
        self.tearMs = tearMs
        self.dropImpulse = dropImpulse
        self.queueStaggerMs = queueStaggerMs
        self.spreadDeg = spreadDeg
        self.impulseVariance = impulseVariance
        self.spin = spin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stepMs = try c.decode(Double.self, forKey: .stepMs)
        stepPx = try c.decode(Double.self, forKey: .stepPx)
        chatterVolume = try c.decode(Double.self, forKey: .chatterVolume)
        dingVolume = try c.decode(Double.self, forKey: .dingVolume)
        tearMs = try c.decode(Double.self, forKey: .tearMs)
        dropImpulse = try c.decode(Double.self, forKey: .dropImpulse)
        queueStaggerMs = try c.decode(Double.self, forKey: .queueStaggerMs)
        spreadDeg = try c.decodeIfPresent(Double.self, forKey: .spreadDeg) ?? 70
        impulseVariance = try c.decodeIfPresent(Double.self, forKey: .impulseVariance) ?? 0.3
        spin = try c.decodeIfPresent(Double.self, forKey: .spin) ?? 0.15
    }
}

/// The stamp rack's geometry and press timings plus ink/haptic feel (spec "The
/// stamp"). The old sweep-arm keyframes (armInMs, overshootPx, settleMs,
/// shiverPx, shiverCount, slamFrames) went away with the arm.
public struct BureauStampTuning: Codable, Equatable, Sendable {
    /// Width of the pulled-out rack panel (the part holding the two heads).
    public var rackWidthPx: Double
    /// Side of a stamp head's square footprint.
    public var stampSizePx: Double
    /// How long the rack takes to slide out or retract.
    public var extendMs: Double
    /// How long the head takes to press down to the desk.
    public var pressMs: Double
    /// How long the head takes to spring back up.
    public var liftMs: Double
    public var inkRotationMinDeg: Double
    public var inkRotationMaxDeg: Double
    public var doubleStrikeOffsetPx: Double
    public var thunkVolume: Double
    public var hapticEnabled: Bool
    /// The mechanical rail sound as the rack slides out or back.
    public var slideVolume: Double

    public init(
        rackWidthPx: Double, stampSizePx: Double, extendMs: Double, pressMs: Double,
        liftMs: Double, inkRotationMinDeg: Double, inkRotationMaxDeg: Double,
        doubleStrikeOffsetPx: Double, thunkVolume: Double, hapticEnabled: Bool,
        slideVolume: Double
    ) {
        self.rackWidthPx = rackWidthPx
        self.stampSizePx = stampSizePx
        self.extendMs = extendMs
        self.pressMs = pressMs
        self.liftMs = liftMs
        self.inkRotationMinDeg = inkRotationMinDeg
        self.inkRotationMaxDeg = inkRotationMaxDeg
        self.doubleStrikeOffsetPx = doubleStrikeOffsetPx
        self.thunkVolume = thunkVolume
        self.hapticEnabled = hapticEnabled
        self.slideVolume = slideVolume
    }

    // A version-2 file carries the old arm keys and none of the rack ones, and a
    // version-3 file has no slideVolume. The extra keys are ignored; the missing
    // keys decode tolerantly to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rackWidthPx = try c.decodeIfPresent(Double.self, forKey: .rackWidthPx) ?? 200
        stampSizePx = try c.decodeIfPresent(Double.self, forKey: .stampSizePx) ?? 64
        extendMs = try c.decodeIfPresent(Double.self, forKey: .extendMs) ?? 220
        pressMs = try c.decodeIfPresent(Double.self, forKey: .pressMs) ?? 90
        liftMs = try c.decodeIfPresent(Double.self, forKey: .liftMs) ?? 130
        inkRotationMinDeg = try c.decode(Double.self, forKey: .inkRotationMinDeg)
        inkRotationMaxDeg = try c.decode(Double.self, forKey: .inkRotationMaxDeg)
        doubleStrikeOffsetPx = try c.decode(Double.self, forKey: .doubleStrikeOffsetPx)
        thunkVolume = try c.decode(Double.self, forKey: .thunkVolume)
        hapticEnabled = try c.decode(Bool.self, forKey: .hapticEnabled)
        slideVolume = try c.decodeIfPresent(Double.self, forKey: .slideVolume) ?? 0.5
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

/// Sticky panel caps and geometry (spec "Pull-out").
public struct BureauStickyTuning: Codable, Equatable, Sendable {
    public var liveCap: Int
    public var subtaskVisibleCap: Int
    /// How much bigger a pulled-out sticky is than the drawer slip it came from
    /// (spec "Pull-out"): the `.full` panel is the slip size times this.
    public var pullOutScale: Double
    /// The portrait drawer slip size, shared by the sprites, the printer, and
    /// the pulled-out sticky (was hardcoded 96x144 in StickyMetrics).
    public var slipWidth: Double
    public var slipHeight: Double
    /// The grow-from-slip spring when a sticky is pulled out (was 0.28 / 0.72).
    public var growSpringResponse: Double
    public var growSpringDamping: Double
    /// The scale a pulled-out sticky grows from; roughly 1/pullOutScale so it
    /// starts at the drawer-slip size.
    public var growStart: Double
    /// Points of a note kept on screen by the off-screen clamp (was 40).
    public var clampMinVisible: Double
    /// How long after the last window move the settle fires (was 350ms).
    public var settleDebounceMs: Double

    public init(
        liveCap: Int, subtaskVisibleCap: Int, pullOutScale: Double,
        slipWidth: Double, slipHeight: Double, growSpringResponse: Double,
        growSpringDamping: Double, growStart: Double, clampMinVisible: Double,
        settleDebounceMs: Double
    ) {
        self.liveCap = liveCap
        self.subtaskVisibleCap = subtaskVisibleCap
        self.pullOutScale = pullOutScale
        self.slipWidth = slipWidth
        self.slipHeight = slipHeight
        self.growSpringResponse = growSpringResponse
        self.growSpringDamping = growSpringDamping
        self.growStart = growStart
        self.clampMinVisible = clampMinVisible
        self.settleDebounceMs = settleDebounceMs
    }

    // A version-1 file has no pullOutScale and a version-2 file none of the
    // geometry fields, so decode every optional tolerantly to its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        liveCap = try c.decode(Int.self, forKey: .liveCap)
        subtaskVisibleCap = try c.decode(Int.self, forKey: .subtaskVisibleCap)
        pullOutScale = try c.decodeIfPresent(Double.self, forKey: .pullOutScale) ?? 1.5
        slipWidth = try c.decodeIfPresent(Double.self, forKey: .slipWidth) ?? 96
        slipHeight = try c.decodeIfPresent(Double.self, forKey: .slipHeight) ?? 144
        growSpringResponse = try c.decodeIfPresent(Double.self, forKey: .growSpringResponse) ?? 0.28
        growSpringDamping = try c.decodeIfPresent(Double.self, forKey: .growSpringDamping) ?? 0.72
        growStart = try c.decodeIfPresent(Double.self, forKey: .growStart) ?? 0.667
        clampMinVisible = try c.decodeIfPresent(Double.self, forKey: .clampMinVisible) ?? 40
        settleDebounceMs = try c.decodeIfPresent(Double.self, forKey: .settleDebounceMs) ?? 350
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

/// The drawer furniture geometry (tray, lip, souvenir stack) and the
/// fresh-spawn tilt (all were hardcoded in `BureauScene`).
public struct BureauDrawerTuning: Codable, Equatable, Sendable {
    public var trayHeightFraction: Double
    public var trayMinHeight: Double
    public var lipHeightPx: Double
    public var traySlotSpacing: Double
    public var trayScale: Double
    public var trayVisibleCap: Int
    public var spawnRotationRange: Double

    public init(
        trayHeightFraction: Double, trayMinHeight: Double, lipHeightPx: Double,
        traySlotSpacing: Double, trayScale: Double, trayVisibleCap: Int, spawnRotationRange: Double
    ) {
        self.trayHeightFraction = trayHeightFraction
        self.trayMinHeight = trayMinHeight
        self.lipHeightPx = lipHeightPx
        self.traySlotSpacing = traySlotSpacing
        self.trayScale = trayScale
        self.trayVisibleCap = trayVisibleCap
        self.spawnRotationRange = spawnRotationRange
    }
}

/// The gentle lay-down when a sticky returns to the drawer (spec R4).
public struct BureauReturnDropTuning: Codable, Equatable, Sendable {
    public var impulse: Double
    public var spin: Double

    public init(impulse: Double, spin: Double) {
        self.impulse = impulse
        self.spin = spin
    }
}

/// The shredder slot: geometry, animation length, and sound volume. The
/// `overlay` sizes are the screen-level shredder panel pinned bottom-right,
/// separate from `widthPx` which is the in-drawer slot inside the scene.
public struct BureauShredderTuning: Codable, Equatable, Sendable {
    public var widthPx: Double
    public var shredMs: Double
    public var volume: Double
    /// The bottom-right overlay panel size, for shredding pulled-out stickies.
    public var overlayWidthPx: Double
    public var overlayHeightPx: Double

    public init(
        widthPx: Double, shredMs: Double, volume: Double,
        overlayWidthPx: Double, overlayHeightPx: Double
    ) {
        self.widthPx = widthPx
        self.shredMs = shredMs
        self.volume = volume
        self.overlayWidthPx = overlayWidthPx
        self.overlayHeightPx = overlayHeightPx
    }

    // A version-3 file has no overlay sizes; decode them tolerantly so the
    // migration fills them without discarding tuned values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        widthPx = try c.decode(Double.self, forKey: .widthPx)
        shredMs = try c.decode(Double.self, forKey: .shredMs)
        volume = try c.decode(Double.self, forKey: .volume)
        overlayWidthPx = try c.decodeIfPresent(Double.self, forKey: .overlayWidthPx) ?? 170
        overlayHeightPx = try c.decodeIfPresent(Double.self, forKey: .overlayHeightPx) ?? 72
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
    public var drawer: BureauDrawerTuning
    public var returnDrop: BureauReturnDropTuning
    public var shredder: BureauShredderTuning

    public init(
        version: Int, transition: BureauTransitionTuning, physics: BureauPhysicsTuning,
        rustle: BureauRustleTuning, print: BureauPrintTuning, stamp: BureauStampTuning,
        crumple: BureauCrumpleTuning, hoverScroll: BureauHoverScrollTuning,
        sticky: BureauStickyTuning, texture: BureauTextureTuning, filedTray: BureauFiledTrayTuning,
        drawer: BureauDrawerTuning, returnDrop: BureauReturnDropTuning, shredder: BureauShredderTuning
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
        self.drawer = drawer
        self.returnDrop = returnDrop
        self.shredder = shredder
    }

    // Version-2 files carry none of the drawer/returnDrop/shredder blocks, so
    // decode them tolerantly to defaults; the per-struct inits above fill the
    // fields added to existing blocks. The migration then bumps to version 3.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        transition = try c.decode(BureauTransitionTuning.self, forKey: .transition)
        physics = try c.decode(BureauPhysicsTuning.self, forKey: .physics)
        rustle = try c.decode(BureauRustleTuning.self, forKey: .rustle)
        print = try c.decode(BureauPrintTuning.self, forKey: .print)
        stamp = try c.decode(BureauStampTuning.self, forKey: .stamp)
        crumple = try c.decode(BureauCrumpleTuning.self, forKey: .crumple)
        hoverScroll = try c.decode(BureauHoverScrollTuning.self, forKey: .hoverScroll)
        sticky = try c.decode(BureauStickyTuning.self, forKey: .sticky)
        texture = try c.decode(BureauTextureTuning.self, forKey: .texture)
        filedTray = try c.decode(BureauFiledTrayTuning.self, forKey: .filedTray)
        drawer = try c.decodeIfPresent(BureauDrawerTuning.self, forKey: .drawer)
            ?? BureauTuningDocument.defaults.drawer
        returnDrop = try c.decodeIfPresent(BureauReturnDropTuning.self, forKey: .returnDrop)
            ?? BureauTuningDocument.defaults.returnDrop
        shredder = try c.decodeIfPresent(BureauShredderTuning.self, forKey: .shredder)
            ?? BureauTuningDocument.defaults.shredder
    }

    /// The values in `bureau-impl.md` section 5, written to disk the first
    /// time the app looks for the tuning file.
    public static let defaults = BureauTuningDocument(
        version: 4,
        transition: BureauTransitionTuning(
            pushMs: 320, easing: [0.16, 1.0, 0.3, 1.0], reduceMotionCrossfadeMs: 160
        ),
        physics: BureauPhysicsTuning(
            repulsionRadius: 90, repulsionStrength: 12, torque: 0.4, friction: 0.7,
            restitution: 0.15, linearDamping: 3.0, angularDamping: 4.0, gravity: 0,
            pushScale: 0.02, torqueScale: 0.001,
            rotationEnabled: true, maxTiltDeg: 180, papersCollide: true
        ),
        rustle: BureauRustleTuning(
            gain: 0.6, velocityThreshold: 0.35, maxVolume: 0.5, rateCapMs: 250, speedRef: 200
        ),
        print: BureauPrintTuning(
            stepMs: 55, stepPx: 6, chatterVolume: 0.4, dingVolume: 0.7,
            tearMs: 180, dropImpulse: 8, queueStaggerMs: 250,
            spreadDeg: 70, impulseVariance: 0.3, spin: 0.15
        ),
        stamp: BureauStampTuning(
            rackWidthPx: 200, stampSizePx: 64, extendMs: 220, pressMs: 90, liftMs: 130,
            inkRotationMinDeg: 2, inkRotationMaxDeg: 4,
            doubleStrikeOffsetPx: 1.5, thunkVolume: 0.8, hapticEnabled: true,
            slideVolume: 0.5
        ),
        crumple: BureauCrumpleTuning(frames: 8, flyToTrayMs: 260),
        hoverScroll: BureauHoverScrollTuning(
            sensitivity: 1.0, inertiaFriction: 0.92, minDelta: 0.5, maxVelocity: 40
        ),
        sticky: BureauStickyTuning(
            liveCap: 12, subtaskVisibleCap: 6, pullOutScale: 1.5,
            slipWidth: 96, slipHeight: 144, growSpringResponse: 0.28, growSpringDamping: 0.72,
            growStart: 0.667, clampMinVisible: 40, settleDebounceMs: 350
        ),
        texture: BureauTextureTuning(rerenderOnEditOnly: true),
        filedTray: BureauFiledTrayTuning(clearsMonday: true),
        drawer: BureauDrawerTuning(
            trayHeightFraction: 0.14, trayMinHeight: 34, lipHeightPx: 6,
            traySlotSpacing: 26, trayScale: 0.45, trayVisibleCap: 8, spawnRotationRange: 0.12
        ),
        returnDrop: BureauReturnDropTuning(impulse: 2, spin: 0.1),
        shredder: BureauShredderTuning(
            widthPx: 56, shredMs: 240, volume: 0.7, overlayWidthPx: 170, overlayHeightPx: 72
        )
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
        // Version 2 changed what the feel values mean (top-down drawer, no
        // gravity, bigger pull-outs), so a version-1 file on disk is stale, not
        // a valid hand edit. Replace it wholesale with the new defaults and
        // write it back so the old gravity never survives a load.
        if doc.version < 2 {
            document = BureauTuningDocument.defaults
            write(BureauTuningDocument.defaults)
            return
        }
        // Versions 3 and 4 only added fields (v3: stamp rack, shredder, drawer
        // geometry, return drop; v4: shredder overlay, rotation control, stamp
        // slide sound). A version-2 or version-3 file already decoded tolerantly
        // above, filling the new fields with defaults while keeping the user's
        // tuned values. Bump it to 4 and write it back so the whole schema is on
        // disk for the slider panel.
        if doc.version == 2 || doc.version == 3 {
            var migrated = doc
            migrated.version = 4
            document = migrated
            write(migrated)
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
