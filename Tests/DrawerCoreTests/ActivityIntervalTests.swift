import XCTest
@testable import DrawerCore

private func t(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
private func range(_ a: TimeInterval, _ b: TimeInterval) -> TimeRange {
    TimeRange(start: t(a), end: t(b))
}

final class ActivityIntervalTests: XCTestCase {
    // MARK: TimeRange

    func testOverlapsIsHalfOpen() {
        // Touching at an endpoint does not overlap ([start, end)).
        XCTAssertFalse(range(0, 10).overlaps(range(10, 20)))
        XCTAssertTrue(range(0, 10).overlaps(range(9, 20)))
    }

    func testClampedToOuter() {
        XCTAssertEqual(range(5, 25).clamped(to: range(0, 20)), range(5, 20))
        XCTAssertNil(range(30, 40).clamped(to: range(0, 20)))
    }

    // MARK: interval subtraction (the stopwatch-overlap invariant)

    func testSubtractLeavesTwoGaps() {
        // 09:00-10:00 minus 09:10-09:20 and 09:35-09:50 => three residual blocks.
        let block = block(0, 3600)
        let residual = block.subtracting([range(600, 1200), range(2100, 2700)])
        XCTAssertEqual(residual.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] },
                       [[0, 600], [1200, 2100], [2700, 3600]])
    }

    func testSubtractMergesOverlappingSpans() {
        let residual = block(0, 100).subtracting([range(10, 40), range(30, 60)])
        XCTAssertEqual(residual.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] },
                       [[0, 10], [60, 100]])
    }

    func testSpanCoveringWholeBlockLeavesNothing() {
        XCTAssertTrue(block(0, 100).subtracting([range(-10, 200)]).isEmpty)
    }

    func testNoOverlapKeepsWholeBlock() {
        let residual = block(0, 100).subtracting([range(200, 300)])
        XCTAssertEqual(residual.count, 1)
        XCTAssertEqual(residual[0].start, t(0))
        XCTAssertEqual(residual[0].end, t(100))
    }

    func testResidualBlocksKeepAppAndTitleEvidence() {
        let residual = block(0, 100, app: "Xcode", titles: ["TodoParser.swift"])
            .subtracting([range(40, 60)])
        XCTAssertEqual(residual.count, 2)
        XCTAssertTrue(residual.allSatisfy { $0.appName == "Xcode" && $0.titles == ["TodoParser.swift"] })
    }

    private func block(
        _ a: TimeInterval, _ b: TimeInterval, app: String = "App", titles: [String] = ["t"]
    ) -> ActivityBlock {
        ActivityBlock(
            start: t(a), end: t(b), bundleID: "com.app", appName: app, titles: titles)
    }
}
