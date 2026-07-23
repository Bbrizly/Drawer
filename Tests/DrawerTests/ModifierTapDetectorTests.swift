import XCTest
@testable import Drawer

final class ModifierTapDetectorTests: XCTestCase {
    func testQuickPressAndReleaseIsATap() {
        var detector = ModifierTapDetector()
        detector.down(at: 0)
        XCTAssertTrue(detector.up(at: 0.1))
    }

    func testHoldingTooLongIsNotATap() {
        var detector = ModifierTapDetector()
        detector.down(at: 0)
        XCTAssertFalse(detector.up(at: 0.6))
    }

    func testAnotherKeyDuringHoldCancelsTheTap() {
        var detector = ModifierTapDetector()
        detector.down(at: 0)
        detector.otherActivity()
        XCTAssertFalse(detector.up(at: 0.1))
    }

    func testReleaseWithoutPressDoesNotFire() {
        var detector = ModifierTapDetector()
        XCTAssertFalse(detector.up(at: 0.1))
    }

    func testSecondTapWorksAfterAFirst() {
        var detector = ModifierTapDetector()
        detector.down(at: 0)
        XCTAssertTrue(detector.up(at: 0.1))
        detector.down(at: 1.0)
        XCTAssertTrue(detector.up(at: 1.05))
    }

    func testActivityBeforeAPressDoesNotCancelTheNextTap() {
        var detector = ModifierTapDetector()
        detector.otherActivity()
        detector.down(at: 0)
        XCTAssertTrue(detector.up(at: 0.1))
    }
}
