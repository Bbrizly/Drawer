import XCTest
@testable import DrawerCore

final class HistoryTimelineTests: XCTestCase {
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    private func snap(_ ts: TimeInterval, _ body: String) -> TimelineSnapshot {
        TimelineSnapshot(ts: t(ts), markdown: "## 2026-07-06\n" + body + "\n")
    }

    func testTaskAppearsInFirstSnapshot() {
        let timeline = HistoryTimelineBuilder.build(snapshots: [snap(0, "- [ ] Ship v2")])
        XCTAssertEqual(timeline.events, [
            TimelineEvent(ts: t(0), identity: "ship v2", title: "Ship v2", kind: .appeared),
        ])
        XCTAssertEqual(timeline.lifecycles.first?.firstSeen, t(0))
    }

    func testCheckingOffEmitsOneEventAndSetsCompletion() {
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Ship v2"),
            snap(100, "- [ ] Ship v2"),
            snap(200, "- [x] Ship v2"),
        ])
        let checks = timeline.events.filter { $0.kind == .checkedOff }
        XCTAssertEqual(checks, [TimelineEvent(ts: t(200), identity: "ship v2", title: "Ship v2", kind: .checkedOff)])
        let life = timeline.lifecycles.first { $0.identity == "ship v2" }
        XCTAssertEqual(life?.completedAt, t(200))
        XCTAssertEqual(life?.survival, 200)
    }

    func testCheckboxToggleIsNotReappearance() {
        // Marker flips but identity is title-based: no second `appeared`.
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Ship v2"),
            snap(100, "- [x] Ship v2"),
        ])
        XCTAssertEqual(timeline.events.filter { $0.kind == .appeared }.count, 1)
    }

    func testMinutesHintChangeIsNotRemoveAndAdd() {
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Ship v2 (25m)"),
            snap(100, "- [ ] Ship v2 (60m)"),
        ])
        XCTAssertTrue(timeline.events.allSatisfy { $0.kind == .appeared })
        XCTAssertEqual(timeline.events.count, 1)
    }

    func testRemovalEmitsRemovedEvent() {
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Ship v2"),
            snap(100, "- [ ] Other"),
        ])
        XCTAssertTrue(timeline.events.contains(
            TimelineEvent(ts: t(100), identity: "ship v2", title: "Ship v2", kind: .removed)))
    }

    func testReappearanceKeepsOriginalFirstSeen() {
        // Removed then re-added: survival spans the whole window, firstSeen holds.
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Ship v2"),
            snap(100, "- [ ] Other"),        // Ship removed
            snap(200, "- [ ] Ship v2"),      // Ship back
        ])
        let life = timeline.lifecycles.first { $0.identity == "ship v2" }
        XCTAssertEqual(life?.firstSeen, t(0))
        XCTAssertEqual(life?.lastSeen, t(200))
        XCTAssertEqual(life?.survival, 200)
    }

    func testUnsortedSnapshotsAreOrderedByTimestamp() {
        // Same data, shuffled: survival must not go negative or wrong.
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(200, "- [ ] Ship v2"),
            snap(0, "- [ ] Ship v2"),
            snap(100, "- [ ] Ship v2"),
        ])
        let life = timeline.lifecycles.first { $0.identity == "ship v2" }
        XCTAssertEqual(life?.firstSeen, t(0))
        XCTAssertEqual(life?.survival, 200)
    }

    func testLongestLivedSortsFirst() {
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            snap(0, "- [ ] Long"),
            snap(100, "- [ ] Long\n- [ ] Short"),
            snap(200, "- [ ] Long\n- [ ] Short"),
        ])
        // Long: 0..200 (200s). Short: 100..200 (100s).
        XCTAssertEqual(timeline.lifecycles.map(\.identity), ["long", "short"])
    }

    func testDailySummaryCountsStartedAndCompletedPerDay() {
        // UTC so day boundaries are deterministic regardless of the test host.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day: TimeInterval = 86_400
        let head = "## 2026-07-06\n"
        let timeline = HistoryTimelineBuilder.build(snapshots: [
            // Day 0: two tasks start, one gets done.
            TimelineSnapshot(ts: t(0), markdown: head + "- [ ] A\n- [ ] B\n"),
            TimelineSnapshot(ts: t(10), markdown: head + "- [x] A\n- [ ] B\n"),
            // Day 1: a new task starts, B gets done.
            TimelineSnapshot(ts: t(day), markdown: head + "- [x] A\n- [ ] B\n- [ ] C\n"),
            TimelineSnapshot(ts: t(day + 10), markdown: head + "- [x] A\n- [x] B\n- [ ] C\n"),
        ])
        let summary = HistoryTimelineBuilder.dailySummary(timeline, calendar: cal)
        XCTAssertEqual(summary.map(\.day), [cal.startOfDay(for: t(0)), cal.startOfDay(for: t(day))])
        XCTAssertEqual(Set(summary[0].started), ["A", "B"])  // both at t(0), order not fixed
        XCTAssertEqual(summary[0].completed, ["A"])
        XCTAssertEqual(summary[1].started, ["C"])
        XCTAssertEqual(summary[1].completed, ["B"])
    }
}
