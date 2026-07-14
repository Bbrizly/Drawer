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
    private var trayHeight: CGFloat { max(34, size.height * 0.14) }

    // MARK: rummage / drag state

    private var lastMouse: CGPoint?
    private var lastMouseTime: TimeInterval = 0
    private var trackingArea: NSTrackingArea?
    private var draggingSprite: ReceiptSprite?
    private var grabOffset: CGPoint = .zero
    private var topZ: CGFloat = 1

    // MARK: settle-persistence state
    private var settleDirty = false
    private var lastActivity: TimeInterval = 0

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        scaleMode = .resizeFill
        backgroundColor = BureauPalette.drawerFloor
        physicsWorld.gravity = CGVector(dx: 0, dy: tuning.physics.gravity)
        rebuildBoundary()
        buildDrawerFurniture()
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
            size: CGSize(width: size.width, height: 6)
        )
        lip.anchorPoint = CGPoint(x: 0, y: 0)
        lip.position = .zero
        lip.zPosition = 100
        addChild(lip)
        lipNode = lip
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
        sprite.zRotation = rotation ?? CGFloat.random(in: -0.12...0.12)
        sprite.applyPhysics(tuning.physics)
        sprite.zPosition = nextZ()
        addChild(sprite)
        settleDirty = true
    }

    /// Drops a freshly torn-off receipt in from the printer seam at the top,
    /// with a downward impulse so it falls into the pile (spec flow b).
    func dropIn(_ sprite: ReceiptSprite) {
        sprite.position = CGPoint(
            x: size.width / 2 + CGFloat.random(in: -12...12),
            y: size.height - sprite.size.height / 2 - 2
        )
        sprite.applyPhysics(tuning.physics)
        sprite.zPosition = nextZ()
        addChild(sprite)
        sprite.physicsBody?.applyImpulse(
            CGVector(dx: CGFloat.random(in: -2...2), dy: -CGFloat(tuning.print.dropImpulse))
        )
        settleDirty = true
    }

    private func nextZ() -> CGFloat {
        topZ += 1
        return topZ
    }

    private var receiptSprites: [ReceiptSprite] {
        children.compactMap { $0 as? ReceiptSprite }
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
        guard let mouse = lastMouse else { return }
        // Manual force loop, active ONLY while the cursor is moving. Once it
        // stops the window goes quiet and bodies settle back to sleep, holding
        // the 0.0% idle CPU contract.
        guard currentTime - lastMouseTime < 0.12 else { return }
        let radius = CGFloat(tuning.physics.repulsionRadius)
        let strength = CGFloat(tuning.physics.repulsionStrength)
        guard radius > 0, strength > 0 else { return }

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
            let push = strength * falloff * 0.02
            body.applyImpulse(CGVector(dx: dx / dist * push, dy: dy / dist * push))
            body.applyAngularImpulse(
                CGFloat(tuning.physics.torque) * falloff * 0.001 * (Bool.random() ? 1 : -1)
            )
            onRustle?(min(1, falloff))
            settleDirty = true
        }
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
        grabOffset = CGPoint(x: p.x - sprite.position.x, y: p.y - sprite.position.y)
        sprite.physicsBody?.isDynamic = false
        sprite.zPosition = nextZ()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let sprite = draggingSprite else { return }
        let p = event.location(in: self)
        sprite.position = CGPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y)
        settleDirty = true
        lastActivity = event.timestamp
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
        draggingSprite?.physicsBody?.isDynamic = true
        draggingSprite = nil
        settleDirty = true
        lastActivity = event.timestamp
    }
}
