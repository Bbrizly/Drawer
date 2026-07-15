import SpriteKit
import XCTest
@testable import DrawerBureau

@MainActor
final class BureauSceneTests: XCTestCase {
    private func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    /// 180 or more means unlimited: the angle passes through untouched, even a
    /// wound-up one, so the free-spin default never re-snaps a slip.
    func testClampTiltUnlimitedPassesThrough() {
        XCTAssertEqual(BureauScene.clampTilt(deg(200), maxDeg: 180), deg(200), accuracy: 1e-6)
        XCTAssertEqual(BureauScene.clampTilt(2.0, maxDeg: 180), 2.0, accuracy: 1e-6)
    }

    /// Past the limit on either side clamps to the limit.
    func testClampTiltClampsBothSigns() {
        XCTAssertEqual(BureauScene.clampTilt(deg(90), maxDeg: 45), deg(45), accuracy: 1e-6)
        XCTAssertEqual(BureauScene.clampTilt(deg(-90), maxDeg: 45), deg(-45), accuracy: 1e-6)
    }

    /// A wound-up angle normalizes into [-pi, pi] first: 350 degrees reads as
    /// -10 degrees, which is inside a 45-degree limit, so it stays -10.
    func testClampTiltNormalizesBeforeClamping() {
        XCTAssertEqual(BureauScene.clampTilt(deg(350), maxDeg: 45), deg(-10), accuracy: 1e-6)
    }

    /// Zero means dead upright.
    func testClampTiltZeroForcesUpright() {
        XCTAssertEqual(BureauScene.clampTilt(deg(30), maxDeg: 0), 0, accuracy: 1e-6)
        XCTAssertEqual(BureauScene.clampTilt(deg(-120), maxDeg: 0), 0, accuracy: 1e-6)
    }

    private let floor = CGRect(x: 0, y: 34, width: 200, height: 300)

    /// A slip already inside the inset rect needs no rescue, so nil comes back.
    func testRescuePositionInsideReturnsNil() {
        XCTAssertNil(BureauScene.rescuePosition(CGPoint(x: 100, y: 200), in: floor, margin: 4))
        // Just inside the inset edge still counts as inside.
        XCTAssertNil(BureauScene.rescuePosition(CGPoint(x: 5, y: 40), in: floor, margin: 4))
    }

    /// Out past one axis clamps that axis to the inset edge and leaves the other.
    func testRescuePositionClampsSingleAxis() {
        let left = BureauScene.rescuePosition(CGPoint(x: -20, y: 200), in: floor, margin: 4)
        XCTAssertEqual(left, CGPoint(x: 4, y: 200))

        let right = BureauScene.rescuePosition(CGPoint(x: 260, y: 200), in: floor, margin: 4)
        XCTAssertEqual(right, CGPoint(x: 196, y: 200))

        let below = BureauScene.rescuePosition(CGPoint(x: 100, y: 10), in: floor, margin: 4)
        XCTAssertEqual(below, CGPoint(x: 100, y: 38))

        let above = BureauScene.rescuePosition(CGPoint(x: 100, y: 500), in: floor, margin: 4)
        XCTAssertEqual(above, CGPoint(x: 100, y: 330))
    }

    /// Far outside both axes clamps both corners back to the inset rect.
    func testRescuePositionClampsBothAxes() {
        let out = BureauScene.rescuePosition(CGPoint(x: -50, y: -50), in: floor, margin: 4)
        XCTAssertEqual(out, CGPoint(x: 4, y: 38))

        let farCorner = BureauScene.rescuePosition(CGPoint(x: 999, y: 999), in: floor, margin: 4)
        XCTAssertEqual(farCorner, CGPoint(x: 196, y: 330))
    }

    /// Setting the scene's tuning with a changed physics block updates a slip
    /// already in the drawer, live: its body picks up the new linear damping.
    func testTuningChangeReappliesPhysicsToSlips() {
        let scene = BureauScene(size: CGSize(width: 200, height: 400))
        var doc = BureauTuningDocument.defaults
        scene.tuning = doc

        let texture = SKTexture()
        let sprite = ReceiptSprite(
            receiptID: UUID(), texture: texture, size: CGSize(width: 96, height: 144)
        )
        scene.addExisting(sprite, at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(sprite.physicsBody?.linearDamping ?? -1, doc.physics.linearDamping, accuracy: 1e-4)

        doc.physics.linearDamping = 7.5
        scene.tuning = doc
        XCTAssertEqual(sprite.physicsBody?.linearDamping ?? -1, 7.5, accuracy: 1e-4)
    }
}
