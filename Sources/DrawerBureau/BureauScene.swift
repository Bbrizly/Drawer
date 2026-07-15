import AppKit
import SpriteKit

/// The rummage drawer. An `SKScene` that draws a drawer floor, a front lip, and
/// a FILED tray at the bottom edge, spawns `ReceiptSprite`s with a physics world
/// tuned from `BureauTuning`, and nudges receipts away from the moving cursor
/// with a manual force loop (spec risk 2: `SKFieldNode` does not reliably wake
/// resting bodies, so the rummage runs impulses only while the cursor moves and
/// lets bodies sleep again the moment it stops).
///
/// The scene owns no file IO and no text drawing. `BureauView` builds sprites
/// from `ReceiptStore` + `TextureRenderer` and hands them in; the scene just
/// runs the world.
final class BureauScene: SKScene {
    /// The live feel values. `BureauView` re-assigns this on hot-reload.
    var tuning: BureauTuningDocument = .defaults {
        didSet { physicsWorld.gravity = CGVector(dx: 0, dy: tuning.physics.gravity) }
    }

    // MARK: R2 seam

    /// Fired the moment a dragged receipt's center leaves the scene bounds.
    /// R1b leaves this nil (the sprite just moves in-scene); R2 wires the
    /// sticky-note handoff to it (spec flow c). Kept as a plain closure so the
    /// pull-out lands cleanly without reworking the scene.
    var onSpriteDraggedPastBounds: ((ReceiptSprite, CGPoint) -> Void)?

    /// Velocity-scaled paper-rustle hook, 0...1. No-op until R4 wires sounds.
    var onRustle: ((CGFloat) -> Void)?

    /// Fired when a slip is dropped into the shredder. The facade deletes only
    /// the RECEIPT (bureau-receipts.json) and plays the shred sound; the task
    /// in Drawer.md is never touched. Fires as the shred begins; the scene runs
    /// the tear-down animation and removes the sprite itself.
    var onShred: ((UUID) -> Void)?

    /// Fires once the drawer has been still for a short beat after any movement,
    /// with each receipt's settled center and rotation, so the facade can save
    /// the layout back to `ReceiptStore` (R2 deliverable 6). Debounced to one
    /// write per rest, not per frame.
    var onReceiptsSettled: (([UUID: (CGPoint, CGFloat)]) -> Void)?

    /// Set once the drawer furniture and the receipts already in the drawer
    /// have been placed. The scene is owned by the facade and outlives the
    /// SwiftUI view, so this guards against re-spawning the same receipts when
    /// the view re-mounts (entering and leaving Bureau mode).
    var isConfigured = false

    // MARK: nodes

    private let trayNode = SKNode()
    private var trayLabel: SKLabelNode?
    private var lipNode: SKSpriteNode?
    /// The dark radial vignette over the whole scene (Papers-Please look). Plain
    /// sprite, no body, sits far above everything so it dims the drawer without
    /// taking any mouse or physics.
    private var vignetteNode: SKSpriteNode?
    private var trayHeight: CGFloat {
        max(CGFloat(tuning.drawer.trayMinHeight), size.height * CGFloat(tuning.drawer.trayHeightFraction))
    }

    // MARK: shredder (bottom-right of the tray strip)

    private var shredderTeeth: [SKSpriteNode] = []
    private var shredderZone: CGRect = .zero
    private var shredderWidth: CGFloat { CGFloat(tuning.shredder.widthPx) }
    private var shredderHovered = false

    // MARK: rummage / drag state

    private var lastMouse: CGPoint?
    private var lastMouseTime: TimeInterval = 0
    private var trackingArea: NSTrackingArea?
    private var draggingSprite: ReceiptSprite?
    private var grabOffset: CGPoint = .zero
    private var topZ: CGFloat = 1
    /// True while the grabbed slip came from the FILED tray (no physics body),
    /// so on release inside the scene it flies back to its slot instead of being
    /// stranded on the floor.
    private var draggingTraySlip = false

    // MARK: settle-persistence state
    private var settleDirty = false
    private var lastActivity: TimeInterval = 0

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        scaleMode = .resizeFill
        backgroundColor = BureauPalette.drawerFloor
        physicsWorld.gravity = CGVector(dx: 0, dy: tuning.physics.gravity)
        rebuildBoundary()
        // The scene is owned by the facade and re-presented on every re-entry
        // into Bureau mode, so didMove runs again. Add the furniture only once:
        // adding trayNode a second time throws (node already has a parent) and
        // crashes the app. The tray and lip persist because the scene is
        // retained; re-laying them out is left to didChangeSize.
        if trayNode.parent == nil {
            buildDrawerFurniture()
        }
        // Mouse-moved events only arrive if the window opts in and the view has
        // a tracking area; without both the rummage never sees the cursor.
        view.window?.acceptsMouseMovedEvents = true
        installTracking(in: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 0, size.height > 0 else { return }
        rebuildBoundary()
        layoutDrawerFurniture()
    }

    // MARK: world

    private func rebuildBoundary() {
        // A physics edge that follows the drawer floor (above the tray) and the
        // walls, so receipts pile in the drawer and land on the tray shelf.
        let floor = CGRect(
            x: 0, y: trayHeight,
            width: size.width, height: max(1, size.height - trayHeight)
        )
        physicsBody = SKPhysicsBody(edgeLoopFrom: floor)
        physicsBody?.friction = CGFloat(tuning.physics.friction)
        // The wall category, so a slip's collisionBitMask can keep colliding
        // with the drawer even when paper-on-paper collision is turned off.
        physicsBody?.categoryBitMask = ReceiptSprite.wallCategory
    }

    private func buildDrawerFurniture() {
        addChild(trayNode)
        layoutDrawerFurniture()
    }

    private func layoutDrawerFurniture() {
        // FILED tray: a visible compartment along the bottom edge. Landing zone
        // and trophy shelf only for now; the stamp/file flow is R4.
        trayNode.removeAllChildren()
        let tray = SKSpriteNode(
            color: BureauPalette.tray,
            size: CGSize(width: size.width, height: trayHeight)
        )
        tray.anchorPoint = CGPoint(x: 0, y: 0)
        tray.position = .zero
        tray.zPosition = 5
        trayNode.addChild(tray)

        let rule = SKSpriteNode(
            color: BureauPalette.drawerLip,
            size: CGSize(width: size.width, height: 2)
        )
        rule.anchorPoint = CGPoint(x: 0, y: 0)
        rule.position = CGPoint(x: 0, y: trayHeight)
        rule.zPosition = 6
        trayNode.addChild(rule)

        let label = SKLabelNode(fontNamed: BureauPalette.pixelFamily)
        label.fontSize = 11
        label.fontColor = BureauPalette.trayInk
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 10, y: trayHeight / 2)
        label.zPosition = 7
        label.text = BureauCopy.filedLabel
        trayNode.addChild(label)
        trayLabel = label

        // Front lip: a darker band drawn in front of the receipts along the
        // very bottom so the drawer reads with depth (the parallax the spec
        // wants between lip, receipts, and floor).
        lipNode?.removeFromParent()
        let lip = SKSpriteNode(
            color: BureauPalette.drawerLip,
            size: CGSize(width: size.width, height: CGFloat(tuning.drawer.lipHeightPx))
        )
        lip.anchorPoint = CGPoint(x: 0, y: 0)
        lip.position = .zero
        lip.zPosition = 100
        addChild(lip)
        lipNode = lip

        // A thin dark gradient strip just above the tray lip, fading up to clear,
        // so the tray reads recessed below the drawer floor.
        let shadow = SKSpriteNode(texture: Self.shadowTexture)
        shadow.anchorPoint = CGPoint(x: 0, y: 0)
        shadow.size = CGSize(width: max(1, size.width), height: 8)
        shadow.position = CGPoint(x: 0, y: trayHeight)
        shadow.zPosition = 6.5
        trayNode.addChild(shadow)

        layoutShredder()
        layoutVignette()
    }

    /// The full-scene vignette (Papers-Please look): a dark radial gradient that
    /// stays clear at the center and darkens toward the edges. The shared static
    /// texture just stretches to the current scene size (layoutDrawerFurniture
    /// runs per resize tick while the panel animates, so no image rendering
    /// here); alpha comes from the texture tuning and 0 disables it.
    private func layoutVignette() {
        guard size.width > 0, size.height > 0 else { return }
        vignetteNode?.removeFromParent()
        let node = SKSpriteNode(texture: Self.vignetteTexture)
        node.anchorPoint = CGPoint(x: 0, y: 0)
        node.position = .zero
        node.size = size
        node.zPosition = 10_000
        node.alpha = CGFloat(tuning.texture.vignetteAlpha)
        addChild(node)
        vignetteNode = node
    }

    /// The vignette gradient rendered once at a fixed reference size: clear
    /// through the middle, ramping to opaque black at the edges. Stretched by
    /// the sprite to the scene size; a stretched radial reads fine at vignette
    /// alpha.
    private static let vignetteTexture: SKTexture = {
        let size = CGSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0, alpha: 0), 0.0),
            (NSColor(calibratedWhite: 0, alpha: 0), 0.55),
            (NSColor(calibratedWhite: 0, alpha: 1), 1.0)
        )
        gradient?.draw(
            in: NSBezierPath(rect: CGRect(origin: .zero, size: size)),
            relativeCenterPosition: .zero
        )
        img.unlockFocus()
        return SKTexture(image: img)
    }()

    /// The recessed-tray shadow gradient rendered once, a 1x8 column dark at the
    /// bottom fading to clear at the top; the sprite stretches it across the
    /// drawer width.
    private static let shadowTexture: SKTexture = {
        let size = CGSize(width: 1, height: 8)
        let img = NSImage(size: size)
        img.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.5),
            NSColor(calibratedWhite: 0, alpha: 0),
        ])
        gradient?.draw(in: CGRect(origin: .zero, size: size), angle: 90)
        img.unlockFocus()
        return SKTexture(image: img)
    }()

    /// The shredder: a dark slot with a row of teeth at the right end of the
    /// tray strip, in the Bureau palette, pure SKNodes. Drop a slip in to
    /// delete just its receipt.
    private func layoutShredder() {
        shredderTeeth.removeAll()
        let width = shredderWidth
        let zone = CGRect(x: size.width - width - 6, y: 3, width: width, height: trayHeight - 6)
        shredderZone = zone

        // The dark slot body.
        let slot = SKSpriteNode(color: BureauPalette.drawerLip, size: zone.size)
        slot.anchorPoint = CGPoint(x: 0, y: 0)
        slot.position = CGPoint(x: zone.minX, y: zone.minY)
        slot.zPosition = 7
        trayNode.addChild(slot)

        // A row of teeth along the top lip of the slot.
        let count = 7
        let tw = zone.width / CGFloat(count)
        for i in 0..<count {
            let tooth = SKSpriteNode(color: BureauPalette.trayInk, size: CGSize(width: tw * 0.7, height: 5))
            tooth.anchorPoint = CGPoint(x: 0.5, y: 1)
            tooth.position = CGPoint(x: zone.minX + (CGFloat(i) + 0.5) * tw, y: zone.maxY)
            tooth.zPosition = 8
            trayNode.addChild(tooth)
            shredderTeeth.append(tooth)
        }

        let label = SKLabelNode(fontNamed: BureauPalette.pixelFamily)
        label.text = BureauCopy.shredderLabel
        label.fontSize = 7
        label.fontColor = BureauPalette.trayInk
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: zone.midX, y: zone.minY + 2)
        label.zPosition = 8
        trayNode.addChild(label)

        applyShredderHighlight()
    }

    /// Brightens the teeth while a dragged slip hovers the slot so the target
    /// reads before release.
    private func setShredderHovered(_ hovered: Bool) {
        guard hovered != shredderHovered else { return }
        shredderHovered = hovered
        applyShredderHighlight()
    }

    private func applyShredderHighlight() {
        let color = shredderHovered ? BureauPalette.stampGreen : BureauPalette.trayInk
        for tooth in shredderTeeth { tooth.color = color }
    }

    /// Updates the tray's lifetime FILED caption (spec Decision 4). Visual only
    /// in R1b; nothing files here yet.
    func setFiledCount(_ count: Int) {
        trayLabel?.text = "\(BureauCopy.filedLabel)  ·  \(BureauCopy.lifetimeFiledCaption(count))"
    }

    // MARK: spawning

    /// Places an already-built sprite at a point in the drawer with a physics
    /// body, for receipts that were already `inDrawer` on mount.
    func addExisting(_ sprite: ReceiptSprite, at point: CGPoint, rotation: CGFloat? = nil) {
        sprite.position = point
        let spawnTilt = CGFloat(tuning.drawer.spawnRotationRange)
        let raw = rotation ?? CGFloat.random(in: -spawnTilt...spawnTilt)
        sprite.zRotation = Self.clampTilt(raw, maxDeg: tuning.physics.maxTiltDeg)
        sprite.applyPhysics(tuning.physics)
        sprite.zPosition = nextZ()
        addChild(sprite)
        settleDirty = true
    }

    /// Tears a fresh receipt off the printer seam at the top and flings it into
    /// the drawer (spec flow b). This is a top-down look with no gravity, so the
    /// slip is thrown in a random direction away from the seam and then glides to
    /// a stop on linear damping, floating where it lands.
    func dropIn(_ sprite: ReceiptSprite) {
        sprite.position = CGPoint(
            x: size.width / 2 + CGFloat.random(in: -12...12),
            y: size.height - sprite.size.height / 2 - 2
        )
        sprite.applyPhysics(tuning.physics)
        sprite.zPosition = nextZ()
        addChild(sprite)
        // A downward-into-scene half-disc: straight down, spread either side, so
        // the slip always heads away from the top edge and never back out the
        // seam.
        let spread = CGFloat.pi * CGFloat(tuning.print.spreadDeg) / 180
        let angle = -CGFloat.pi / 2 + CGFloat.random(in: -spread...spread)
        let variance = CGFloat(tuning.print.impulseVariance)
        let magnitude = CGFloat(tuning.print.dropImpulse) * CGFloat.random(in: (1 - variance)...(1 + variance))
        sprite.physicsBody?.applyImpulse(
            CGVector(dx: cos(angle) * magnitude, dy: sin(angle) * magnitude)
        )
        // A calmer fresh-print spin than the old range, which flung the slip
        // around the drawer.
        let spin = CGFloat(tuning.print.spin)
        sprite.physicsBody?.applyAngularImpulse(CGFloat.random(in: -spin...spin))
        settleDirty = true
    }

    /// Lays a receipt back down where a sticky was dropped (spec R4 return
    /// path): placed at `point` (clamped inside the floor) or the drawer center
    /// if nil, with a small nudge and a small spin, about a quarter of the
    /// print's, so it reads as setting a paper down rather than throwing it.
    func returnToDrawer(_ sprite: ReceiptSprite, at point: CGPoint?) {
        let floor = CGRect(
            x: 0, y: trayHeight, width: size.width, height: max(1, size.height - trayHeight)
        )
        let target: CGPoint
        if let p = point {
            target = CGPoint(
                x: min(max(p.x, floor.minX + 20), floor.maxX - 20),
                y: min(max(p.y, floor.minY + 20), floor.maxY - 20)
            )
        } else {
            target = CGPoint(x: floor.midX, y: floor.midY)
        }
        sprite.position = target
        let spawnTilt = CGFloat(tuning.drawer.spawnRotationRange)
        sprite.zRotation = Self.clampTilt(
            CGFloat.random(in: -spawnTilt...spawnTilt), maxDeg: tuning.physics.maxTiltDeg
        )
        sprite.applyPhysics(tuning.physics)
        sprite.zPosition = nextZ()
        if sprite.parent == nil { addChild(sprite) }
        let impulse = CGFloat(tuning.returnDrop.impulse)
        let spin = CGFloat(tuning.returnDrop.spin)
        sprite.physicsBody?.applyImpulse(CGVector(
            dx: CGFloat.random(in: -impulse...impulse),
            dy: CGFloat.random(in: -impulse...impulse)
        ))
        sprite.physicsBody?.applyAngularImpulse(CGFloat.random(in: -spin...spin))
        settleDirty = true
    }

    private func nextZ() -> CGFloat {
        topZ += 1
        return topZ
    }

    /// Swaps the pre-rendered texture on a slip already in the scene, so a
    /// texture-tuning edit (the stub-line toggle) lands on loose drawer slips and
    /// filed tray slips without a re-spawn. The caller regenerates the image with
    /// the slip's own title and age; size and scale are untouched.
    func swapTexture(receiptID: UUID, texture: SKTexture) {
        for sprite in receiptSprites where sprite.receiptID == receiptID {
            sprite.texture = texture
        }
    }

    // MARK: FILED tray (R4)

    /// How many slips the tray shows stacked before older ones just add to the
    /// caption; keeps the trophy shelf readable at 100 filed.
    private var trayVisibleCap: Int { max(1, tuning.drawer.trayVisibleCap) }
    private var trayScale: CGFloat { CGFloat(tuning.drawer.trayScale) }
    private var traySlotSpacing: CGFloat { CGFloat(tuning.drawer.traySlotSpacing) }

    /// The slips currently resting in the tray (a filed souvenir has no physics
    /// body and sits on the shelf). Counting them from the children lets the
    /// bookkeeping survive a slip being pulled out or shredded, rather than a
    /// standing counter drifting.
    private func trayedSlips(excluding: ReceiptSprite? = nil) -> [ReceiptSprite] {
        receiptSprites.filter {
            $0 !== excluding && $0.physicsBody == nil && $0.position.y <= trayHeight + 1
        }
    }

    /// A DONE receipt arriving in the tray (spec "The stamp"): the slip
    /// crumples over `crumple.frames`, flies to its stack slot over
    /// `flyToTrayMs`, and lands flat with the stamp showing. Also the landing
    /// spot for a filed slip pulled back out and let go, which just flies to its
    /// slot with no crumple replay.
    func fileIntoTray(_ sprite: ReceiptSprite, animated: Bool = true, crumple: Bool = true) {
        sprite.physicsBody = nil
        if sprite.parent == nil {
            sprite.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
            addChild(sprite)
        }
        stampTrayInk(on: sprite)
        let index = trayedSlips(excluding: sprite).count
        let slot = traySlot(index: index)
        sprite.zPosition = 6 + CGFloat(index + 1) * 0.01

        guard animated else {
            settleInTray(sprite, at: slot, index: index)
            return
        }
        var pre: [SKAction] = []
        if crumple {
            // The crumple: quick alternating pinches, chunky on purpose.
            let frames = max(1, tuning.crumple.frames)
            for i in 0..<frames {
                let squeezeX: CGFloat = i.isMultiple(of: 2) ? 0.75 : 0.9
                let squeezeY: CGFloat = i.isMultiple(of: 2) ? 0.9 : 0.72
                pre.append(.group([
                    .scaleX(to: squeezeX, y: squeezeY, duration: 0.02),
                    .rotate(byAngle: i.isMultiple(of: 2) ? 0.08 : -0.08, duration: 0.02),
                ]))
            }
        }
        let fly = SKAction.group([
            .move(to: slot, duration: max(0.05, tuning.crumple.flyToTrayMs / 1000)),
            .rotate(toAngle: slotRotation(index: index), duration: max(0.05, tuning.crumple.flyToTrayMs / 1000)),
        ])
        fly.timingMode = .easeIn
        sprite.run(.sequence([.sequence(pre), fly])) { [weak self, weak sprite] in
            guard let self, let sprite else { return }
            self.settleInTray(sprite, at: slot, index: index)
        }
    }

    private func settleInTray(_ sprite: ReceiptSprite, at slot: CGPoint, index: Int) {
        sprite.position = slot
        sprite.setScale(trayScale)
        sprite.zRotation = slotRotation(index: index)
        if index >= trayVisibleCap { sprite.removeFromParent() }
    }

    private func traySlot(index: Int) -> CGPoint {
        // Stacked flat left-to-right along the shelf, a fixed overlap per slip,
        // stopping short of the shredder slot at the far right.
        let x = 66 + CGFloat(min(index, trayVisibleCap - 1)) * traySlotSpacing
        let rightLimit = size.width - shredderWidth - 20
        return CGPoint(x: min(x, rightLimit), y: trayHeight / 2)
    }

    /// A small, stable per-slip tilt so the stack reads as real paper without
    /// looking messy. Deterministic in the index so a slip does not re-tilt.
    private func slotRotation(index: Int) -> CGFloat {
        let jitter: [CGFloat] = [0.04, -0.05, 0.03, -0.03, 0.05, -0.04, 0.02, -0.02]
        return jitter[index % jitter.count]
    }

    /// A little APPROVED mark on the tray souvenir so the stack reads "stamped",
    /// per Decision 4's trophy shelf. Sized to fit the mini slip and rotated a
    /// touch. Idempotent (named node) so a pulled-out slip returning does not
    /// stack a second mark.
    private func stampTrayInk(on sprite: ReceiptSprite) {
        guard sprite.childNode(withName: "trayInk") == nil else { return }
        let label = SKLabelNode(fontNamed: BureauPalette.pixelFamily)
        label.name = "trayInk"
        label.text = BureauCopy.doneStampLabel
        label.fontSize = 13
        label.fontColor = BureauPalette.stampGreen
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zRotation = 0.08
        label.zPosition = 1
        sprite.addChild(label)
    }

    /// The Monday ceremony (spec Decision 4): the filed stack drops off the
    /// shelf and fades, leaving the engraved lifetime count.
    func clearTray() {
        for (i, sprite) in trayedSlips().enumerated() {
            let drop = SKAction.sequence([
                .wait(forDuration: Double(i) * 0.06),
                .group([
                    .moveBy(x: 0, y: -trayHeight, duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                ]),
                .removeFromParent(),
            ])
            drop.timingMode = .easeIn
            sprite.run(drop)
        }
    }

    private var receiptSprites: [ReceiptSprite] {
        children.compactMap { $0 as? ReceiptSprite }
    }

    // MARK: shredder

    /// Feeds a slip into the shredder: the receipt is deleted (via `onShred`,
    /// which the facade routes to `ReceiptStore.remove` and the shred sound;
    /// the Drawer.md task is never touched), then the slip snaps upright over
    /// the slot and slides down while squeezing narrow and fading, in the same
    /// chunky step style as the crumple.
    private func shred(_ sprite: ReceiptSprite) {
        let id = sprite.receiptID
        sprite.physicsBody = nil
        setShredderHovered(false)
        onShred?(id)

        // Snap upright, centered over the slot mouth.
        let mouth = CGPoint(x: shredderZone.midX, y: shredderZone.maxY + sprite.size.height * sprite.yScale * 0.3)
        let align = SKAction.group([
            .move(to: mouth, duration: 0.08),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        // Chunky downward steps: squeeze X, drop, fade.
        let shredMs = tuning.shredder.shredMs
        let n = 6
        let stepDur = shredMs / 1000 / Double(n)
        var steps: [SKAction] = []
        for i in 0..<n {
            let f = CGFloat(i + 1) / CGFloat(n)
            steps.append(.group([
                .scaleX(to: max(0.06, (1 - f) * sprite.xScale), y: sprite.yScale, duration: stepDur),
                .moveBy(x: 0, y: -shredderZone.height / CGFloat(n), duration: stepDur),
                .fadeAlpha(to: max(0, 1 - f), duration: stepDur),
            ]))
        }
        sprite.run(.sequence([align, .sequence(steps), .removeFromParent()]))
    }

    // MARK: rummage

    private func installTracking(in view: SKView) {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouse = event.location(in: self)
        lastMouseTime = event.timestamp
    }

    override func update(_ currentTime: TimeInterval) {
        detectSettle(currentTime)
        enforceRotationRules()
        guard let mouse = lastMouse else { return }
        // Manual force loop, active ONLY while the cursor is moving. Once it
        // stops the window goes quiet and bodies settle back to sleep, holding
        // the 0.0% idle CPU contract.
        guard currentTime - lastMouseTime < 0.12 else { return }
        let radius = CGFloat(tuning.physics.repulsionRadius)
        let strength = CGFloat(tuning.physics.repulsionStrength)
        guard radius > 0, strength > 0 else { return }

        // The rustle tracks how fast the paper actually moves, taken once across
        // every moved slip. Firing per-sprite off cursor proximity let a plain
        // hover machine-gun the sound, so one call per tick at the top speed.
        var maxRustle: CGFloat = 0
        for sprite in receiptSprites where sprite !== draggingSprite {
            guard let body = sprite.physicsBody else { continue }
            let dx = sprite.position.x - mouse.x
            let dy = sprite.position.y - mouse.y
            let dist = max(1, (dx * dx + dy * dy).squareRoot())
            guard dist < radius else { continue }
            let falloff = 1 - dist / radius
            // Impulses (not forces) so a resting body actually wakes; forces
            // are ignored by a sleeping body.
            body.isResting = false
            let push = strength * falloff * CGFloat(tuning.physics.pushScale)
            body.applyImpulse(CGVector(dx: dx / dist * push, dy: dy / dist * push))
            body.applyAngularImpulse(
                CGFloat(tuning.physics.torque) * falloff * CGFloat(tuning.physics.torqueScale) * (Bool.random() ? 1 : -1)
            )
            let speed = hypot(body.velocity.dx, body.velocity.dy)
            let speedRef = max(1, CGFloat(tuning.rustle.speedRef))
            maxRustle = max(maxRustle, min(1, speed / speedRef))
            settleDirty = true
        }
        if maxRustle > 0 { onRustle?(maxRustle) }
    }

    /// Applies the live rotation/collision tuning to every slip each frame, so a
    /// slider toggle in the tuning panel takes effect on bodies already in the
    /// drawer. Writes only on change so a resting body is not woken needlessly.
    /// When a tilt limit is set, a slip that has spun past it is clamped back and
    /// its spin dampened so it reads as bumping a rotational stop.
    private func enforceRotationRules() {
        let p = tuning.physics
        let rot = p.rotationEnabled
        let collide = p.papersCollide
        let target: UInt32 = collide
            ? (ReceiptSprite.slipCategory | ReceiptSprite.wallCategory)
            : ReceiptSprite.wallCategory
        for sprite in receiptSprites {
            guard let body = sprite.physicsBody else { continue }
            if body.allowsRotation != rot { body.allowsRotation = rot }
            if body.categoryBitMask != ReceiptSprite.slipCategory {
                body.categoryBitMask = ReceiptSprite.slipCategory
            }
            if body.collisionBitMask != target { body.collisionBitMask = target }
            guard p.maxTiltDeg < 180 else { continue }
            let clamped = Self.clampTilt(sprite.zRotation, maxDeg: p.maxTiltDeg)
            if clamped != sprite.zRotation {
                sprite.zRotation = clamped
                // A small negative multiplier so it bounces off the stop rather
                // than freezing dead.
                body.angularVelocity *= -0.2
            }
        }
    }

    /// Normalizes an angle to [-pi, pi] and clamps it to `maxDeg` from upright.
    /// `maxDeg >= 180` means unlimited, so the angle passes through untouched.
    /// Pure and static so it is tested without a scene.
    static func clampTilt(_ angle: CGFloat, maxDeg: Double) -> CGFloat {
        guard maxDeg < 180 else { return angle }
        let normalized = atan2(sin(angle), cos(angle))
        let limit = CGFloat(maxDeg) * .pi / 180
        return min(max(normalized, -limit), limit)
    }

    /// Debounced layout save: whenever any body is moving, mark the drawer dirty
    /// and note the time; once everything has been still for a beat, emit each
    /// receipt's settled center and rotation exactly once. A drag holds a body
    /// non-dynamic (zero velocity), so `mouseDragged`/`mouseUp` mark activity
    /// directly for it.
    private func detectSettle(_ currentTime: TimeInterval) {
        let moving = receiptSprites.contains { sprite in
            guard let b = sprite.physicsBody else { return false }
            return hypot(b.velocity.dx, b.velocity.dy) > 2 || abs(b.angularVelocity) > 0.2
        }
        if moving {
            settleDirty = true
            lastActivity = currentTime
        } else if settleDirty, currentTime - lastActivity > 0.4 {
            settleDirty = false
            guard onReceiptsSettled != nil else { return }
            var layout: [UUID: (CGPoint, CGFloat)] = [:]
            for sprite in receiptSprites where sprite !== draggingSprite {
                layout[sprite.receiptID] = (sprite.position, sprite.zRotation)
            }
            if !layout.isEmpty { onReceiptsSettled?(layout) }
        }
    }

    // MARK: dragging (R1b: in-scene only; R2 takes over past the bounds)

    override func mouseDown(with event: NSEvent) {
        let p = event.location(in: self)
        guard let sprite = nodes(at: p).compactMap({ $0 as? ReceiptSprite }).first else { return }
        draggingSprite = sprite
        draggingTraySlip = sprite.physicsBody == nil
        grabOffset = CGPoint(x: p.x - sprite.position.x, y: p.y - sprite.position.y)
        // A tray slip lifts back to full size in the hand so it drags like a
        // drawer receipt (and hands off to a sticky past the bounds).
        if draggingTraySlip { sprite.setScale(1) }
        sprite.physicsBody?.isDynamic = false
        sprite.zPosition = nextZ()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sprite = draggingSprite else { return }
        let p = event.location(in: self)
        sprite.position = CGPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
        settleDirty = true
        lastActivity = event.timestamp
        // Light up the shredder while the slip hovers its slot.
        setShredderHovered(shredderZone.contains(sprite.position))
        if let handoff = onSpriteDraggedPastBounds, !frame.contains(sprite.position) {
            // The R2 handoff seam (flow c): the sprite's center left the scene,
            // so the sticky layer takes over the drag. Stop tracking it here
            // (and fire once) so the scene and the follow monitor never both
            // move it. With no handler wired the whole branch is skipped and the
            // sprite keeps moving in-scene, R1b's fallback behavior.
            draggingSprite = nil
            handoff(sprite, p)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            draggingSprite = nil
            settleDirty = true
            lastActivity = event.timestamp
        }
        guard let sprite = draggingSprite else { return }
        if shredderZone.contains(sprite.position) {
            shred(sprite)
            return
        }
        setShredderHovered(false)
        if draggingTraySlip {
            // A filed slip dropped back in the scene flies to its tray slot
            // rather than being stranded on the floor with no physics.
            fileIntoTray(sprite, animated: true, crumple: false)
            return
        }
        sprite.physicsBody?.isDynamic = true
    }
}
