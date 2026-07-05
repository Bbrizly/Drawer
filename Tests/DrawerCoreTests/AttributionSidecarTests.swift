import XCTest
@testable import DrawerCore

private final class Box: @unchecked Sendable { var text = "" }

final class AttributionSidecarTests: XCTestCase {
    // MARK: coalesce

    func testCoalesceDropsConsecutiveSameTitleFlaps() {
        let s = { (ts: TimeInterval, app: String, title: String) in
            ActivitySample(ts: Date(timeIntervalSince1970: ts), bundleID: "com.\(app)", appName: app, windowTitle: title)
        }
        let coalesced = coalesceSamples([
            s(0, "Xcode", "Foo.swift"),
            s(1, "Xcode", "Foo.swift - Edited"),  // normalizes equal -> dropped
            s(2, "Xcode", "Bar.swift"),           // new title -> kept
            s(3, "Slack", "general"),
            s(4, "Slack", "general"),              // same -> dropped
        ])
        XCTAssertEqual(coalesced.map(\.windowTitle), ["Foo.swift", "Bar.swift", "general"])
    }

    // MARK: raw-activity 7-day prune

    func testPruneKeepsLastSevenDays() throws {
        let box = Box()
        let store = RawActivityStore(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            read: { _ in box.text }, appendLine: { l, _ in box.text += l },
            overwrite: { v, _ in box.text = v })
        let now = Date(timeIntervalSince1970: 8 * 86400)
        try store.append(ActivitySample(ts: Date(timeIntervalSince1970: 0), bundleID: "a", appName: "a")) // 8 days old
        try store.append(ActivitySample(ts: Date(timeIntervalSince1970: 7 * 86400), bundleID: "b", appName: "b")) // 1 day old
        store.prune(now: now)
        XCTAssertEqual(store.all().map(\.bundleID), ["b"])
    }

    // MARK: day-summary sidecar

    func testDaySummaryUpsertLastWins() throws {
        let box = Box()
        let store = DaySummaryStore(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            read: { _ in box.text }, appendLine: { l, _ in box.text += l },
            overwrite: { v, _ in box.text = v })
        try store.upsert(day: "2026-07-05", summary: "first", generatedAt: Date(timeIntervalSince1970: 0))
        try store.upsert(day: "2026-07-05", summary: "second", generatedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(store.byDay()["2026-07-05"], "second")
    }

    // MARK: markdown merge

    func testWorkLogMergesDaySummaryUnderHeading() {
        let summary = WorkSummary(
            day: "2026-07-05",
            rows: [WorkSummary.Row(taskTitle: "Ship", seconds: 3600)],
            total: 3600, longest: nil)
        let md = renderWorkLogMarkdown([summary], daySummaries: ["2026-07-05": "A focused day shipping."])
        let lines = md.components(separatedBy: "\n")
        let headingIdx = lines.firstIndex { $0.hasPrefix("## 2026-07-05") }!
        // The narrative sits directly under the day heading, above the rows.
        XCTAssertEqual(lines[headingIdx + 1], "A focused day shipping.")
        XCTAssertTrue(md.contains("- Ship —"))
    }

    func testWorkLogWithoutSummaryUnchanged() {
        let summary = WorkSummary(day: "2026-07-05", rows: [], total: 0, longest: nil)
        let md = renderWorkLogMarkdown([summary])
        XCTAssertFalse(md.contains("A focused day"))
        XCTAssertTrue(md.contains("## 2026-07-05"))
    }
}
