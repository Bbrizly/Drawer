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
}
