import XCTest
@testable import Drawer

@MainActor
final class SwipeCoordinatorTests: XCTestCase {
    func testRightSwipePastThresholdFiresProgressOnce() {
        let swipe = SwipeCoordinator()
        var fired: [String] = []
        swipe.onProgress = { fired.append($0) }

        swipe.drag(id: "a", translationX: swipe.progressWidth) // full right swipe
        swipe.end(id: "a")

        XCTAssertEqual(fired, ["a"]) // exactly one fire, right id
        XCTAssertEqual(swipe.offset(for: "a"), 0) // snapped back to rest
        XCTAssertFalse(swipe.isOpen("a")) // progress never holds the row open
    }

    func testRightSwipeBelowThresholdDoesNotFire() {
        let swipe = SwipeCoordinator()
        var fired = 0
        swipe.onProgress = { _ in fired += 1 }

        swipe.drag(id: "a", translationX: swipe.progressWidth / 2 - 1)
        swipe.end(id: "a")

        XCTAssertEqual(fired, 0)
        XCTAssertEqual(swipe.offset(for: "a"), 0)
    }

    func testLeftSwipeOpensDeleteWithoutFiringProgress() {
        let swipe = SwipeCoordinator()
        var fired = 0
        swipe.onProgress = { _ in fired += 1 }

        swipe.drag(id: "a", translationX: -swipe.deleteWidth)
        swipe.end(id: "a")

        XCTAssertEqual(fired, 0) // a delete swipe is not a progress swipe
        XCTAssertTrue(swipe.isOpen("a")) // delete button stays revealed
        XCTAssertEqual(swipe.offset(for: "a"), -swipe.deleteWidth)
    }

    func testDraggingAnotherRowClosesTheOpenOne() {
        let swipe = SwipeCoordinator()
        swipe.drag(id: "a", translationX: -swipe.deleteWidth)
        swipe.end(id: "a")
        XCTAssertTrue(swipe.isOpen("a"))

        swipe.drag(id: "b", translationX: 10)
        XCTAssertEqual(swipe.offset(for: "a"), 0) // the open row snaps shut
        XCTAssertFalse(swipe.isOpen("a"))
    }

    func testBoardCoverageBySwipe() {
        // 150 points of swipe from 0 raises coverage by 150/300 = 0.5.
        XCTAssertEqual(SwipeCoordinator.coverage(from: 0, dx: 150), 0.5, accuracy: 0.0001)
        // Clamps to fully covered and to zero.
        XCTAssertEqual(SwipeCoordinator.coverage(from: 0.9, dx: 300), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SwipeCoordinator.coverage(from: 0.2, dx: -200), 0.0, accuracy: 0.0001)
    }

    func testOneSwipeFromFullCoverageCloses() {
        // 300 points shrinks a full-screen board back to the normal panel, and
        // the next 50 take it past the end of the track, which is the close.
        // The raw value is what the monitor tests, so a single gesture is
        // enough. It used to need a second one starting at zero coverage.
        XCTAssertGreaterThan(SwipeCoordinator.rawCoverage(from: 1, dx: -300), -50.0 / 300)
        XCTAssertLessThanOrEqual(SwipeCoordinator.rawCoverage(from: 1, dx: -360), -50.0 / 300)
    }
}
