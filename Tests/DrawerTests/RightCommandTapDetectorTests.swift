import XCTest
@testable import Drawer

final class RightCommandTapDetectorTests: XCTestCase {
    func testQuickPressAndReleaseIsATap() {
        var detector = RightCommandTapDetector()
        detector.commandDown(at: 0)
        XCTAssertTrue(detector.commandUp(at: 0.1))
    }

    func testHoldingTooLongIsNotATap() {
        var detector = RightCommandTapDetector()
        detector.commandDown(at: 0)
        XCTAssertFalse(detector.commandUp(at: 0.6))
    }

    func testAnotherKeyDuringHoldCancelsTheTap() {
        var detector = RightCommandTapDetector()
        detector.commandDown(at: 0)
        detector.otherActivity()
        XCTAssertFalse(detector.commandUp(at: 0.1))
    }

    func testReleaseWithoutPressDoesNotFire() {
        var detector = RightCommandTapDetector()
        XCTAssertFalse(detector.commandUp(at: 0.1))
    }

    func testSecondTapWorksAfterAFirst() {
        var detector = RightCommandTapDetector()
        detector.commandDown(at: 0)
        XCTAssertTrue(detector.commandUp(at: 0.1))
        detector.commandDown(at: 1.0)
        XCTAssertTrue(detector.commandUp(at: 1.05))
    }

    func testActivityBeforeAPressDoesNotCancelTheNextTap() {
        var detector = RightCommandTapDetector()
        detector.otherActivity()
        detector.commandDown(at: 0)
        XCTAssertTrue(detector.commandUp(at: 0.1))
    }
}
