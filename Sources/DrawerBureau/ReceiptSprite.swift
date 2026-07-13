import SpriteKit

/// A single printed receipt in the drawer scene: a sprite that carries its
/// `ReceiptLink` id and a pre-rendered, nearest-filtered texture. It draws no
/// text itself (that is baked into the texture by `TextureRenderer`); it only
/// displays the texture and holds a physics body so it can tumble and settle.
final class ReceiptSprite: SKSpriteNode {
    let receiptID: UUID

    init(receiptID: UUID, texture: SKTexture, size: CGSize) {
        self.receiptID = receiptID
        texture.filteringMode = .nearest
        super.init(texture: texture, color: .clear, size: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Gives the slip a physics body sized just inside the paper, with the feel
    /// values from `BureauTuning`. A light mass and the tuned damping let bodies
    /// settle and then sleep (`isResting`) so a still drawer costs no CPU.
    func applyPhysics(_ p: BureauPhysicsTuning) {
        let body = SKPhysicsBody(
            rectangleOf: CGSize(width: size.width * 0.9, height: size.height * 0.8)
        )
        body.friction = CGFloat(p.friction)
        body.restitution = CGFloat(p.restitution)
        body.linearDamping = CGFloat(p.linearDamping)
        body.angularDamping = CGFloat(p.angularDamping)
        body.allowsRotation = true
        // ponytail: fixed light mass. Fine for uniform slips; if receipts ever
        // vary in size enough to want different heft, derive mass from area.
        body.mass = 0.05
        physicsBody = body
    }
}
