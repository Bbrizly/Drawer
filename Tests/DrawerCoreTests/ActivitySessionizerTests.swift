import XCTest
@testable import DrawerCore

private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

private func sample(_ ts: TimeInterval, _ app: String, _ title: String) -> ActivitySample {
    ActivitySample(ts: at(ts), bundleID: "com.\(app)", appName: app, windowTitle: title)
}

/// Samples are state changes; blocks close on the next different sample, an
/// explicit boundary, or streamEnd.
final class ActivitySessionizerTests: XCTestCase {
    private func blocks(
        _ samples: [ActivitySample], boundaries: [SessionBoundary] = [], streamEnd: TimeInterval
    ) -> [ActivityBlock] {
        ActivitySessionizer.sessionize(samples: samples, boundaries: boundaries, streamEnd: at(streamEnd))
    }

    func testTitleFlapStaysOneBlock() {
        let out = blocks([
            sample(0, "Xcode", "Foo.swift"),
            sample(60, "Xcode", "Foo.swift - Edited"), // normalizes equal
        ], streamEnd: 180)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].start, at(0))
        XCTAssertEqual(out[0].end, at(180))
        XCTAssertEqual(out[0].titles, ["Foo.swift", "Foo.swift - Edited"])
    }

    func testAppChangeSplitsBlocks() {
        let out = blocks([
            sample(0, "Xcode", "Foo.swift"),
            sample(120, "Slack", "general"),
        ], streamEnd: 240)
        XCTAssertEqual(out.map(\.appName), ["Xcode", "Slack"])
        XCTAssertEqual(out[0].end, at(120)) // Xcode ends exactly when Slack opens
        XCTAssertEqual(out[1].end, at(240))
    }

    func testDifferentTitleSameAppSplits() {
        // A different document in the same app is a different cluster => new block.
        let out = blocks([
            sample(0, "Xcode", "Foo.swift"),
            sample(120, "Xcode", "Bar.swift"),
        ], streamEnd: 240)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1].titles, ["Bar.swift"])
    }

    func testIdleBoundaryClosesBlock() {
        let out = blocks(
            [sample(0, "Xcode", "Foo"), sample(300, "Xcode", "Foo")],
            boundaries: [SessionBoundary(ts: at(120), reason: .idle)],
            streamEnd: 400)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].closeReason, .idle)
        XCTAssertEqual(out[0].end, at(120))
        XCTAssertEqual(out[1].start, at(300))
    }

    func testSleepBoundaryClosesBlock() {
        let out = blocks(
            [sample(0, "Xcode", "Foo"), sample(160, "Xcode", "Foo")],
            boundaries: [SessionBoundary(ts: at(120), reason: .sleep)],
            streamEnd: 240)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].closeReason, .sleep)
        XCTAssertEqual(out[0].end, at(120))
        XCTAssertEqual(out[1].start, at(160))
    }

    func testShortBlockDropped() {
        let out = blocks([
            sample(0, "Xcode", "Foo"),
            sample(120, "Preview", "diagram"), // 5s block, dropped
            sample(125, "Terminal", "zsh"),
        ], streamEnd: 300)
        XCTAssertEqual(out.map(\.appName), ["Xcode", "Terminal"])
    }

    func testShortExcursionBridgesSameAppBlocks() {
        let out = blocks([
            sample(0, "Xcode", "Foo.swift"),
            sample(120, "Slack", "ping"), // 3s blip
            sample(123, "Xcode", "Foo.swift"),
        ], streamEnd: 250)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].appName, "Xcode")
        XCTAssertEqual(out[0].start, at(0))
        XCTAssertEqual(out[0].end, at(250))
    }

    func testLongExcursionDoesNotBridge() {
        let out = blocks([
            sample(0, "Xcode", "Foo"),
            sample(120, "Slack", "general"), // 180s real block
            sample(300, "Xcode", "Foo"),
        ], streamEnd: 420)
        XCTAssertEqual(out.map(\.appName), ["Xcode", "Slack", "Xcode"])
    }
}
