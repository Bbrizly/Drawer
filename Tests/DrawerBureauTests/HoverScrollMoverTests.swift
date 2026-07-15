import XCTest
@testable import DrawerBureau

@MainActor
final class HoverScrollMoverTests: XCTestCase {
    /// The warp target is the mouse plus the window delta, flipped from AppKit's
    /// bottom-left origin into Quartz's top-left origin against the primary
    /// display height. Mouse (100, 200) moved by (10, -5) on a 900-tall display
    /// lands at (110, 900 - 195).
    func testWarpTargetFlipsYAndAddsDelta() {
        let t = HoverScrollMover.warpTarget(
            mouse: CGPoint(x: 100, y: 200), dx: 10, dy: -5, primaryMaxY: 900
        )
        XCTAssertEqual(t.x, 110, accuracy: 1e-6)
        XCTAssertEqual(t.y, 900 - 195, accuracy: 1e-6)
    }
}
