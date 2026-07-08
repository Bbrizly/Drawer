import XCTest
@testable import DrawerCore

/// The accept-time conversion: an edited planner draft becomes the sidecar
/// `DaySchedule`. Link anchors (originalID/sectionDate/normalizedTitle) must be
/// captured here so reconciliation can re-attach blocks to live tasks later.
final class ScheduleFromDraftTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    func testDraftEntryWithTaskIDCapturesSectionDateAndTitleAnchors() {
        let task = TodoItem(
            rawLine: "- [ ] Ship v2", title: "Ship v2", isDone: false,
            minutes: 25, sectionDate: "2026-07-06")
        let entry = PlanDraftEntry(title: "Ship v2", taskID: task.id, minutes: 90, reason: "biggest rock")

        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "h",
            draft: [entry], liveTasks: [task])

        XCTAssertEqual(schedule.blocks.count, 1)
        let block = schedule.blocks[0]
        XCTAssertEqual(block.originalID, task.id)
        XCTAssertEqual(block.sectionDate, "2026-07-06")
        XCTAssertEqual(block.normalizedTitle, TitleSimilarity.normalize("Ship v2"))
        XCTAssertEqual(block.minutes, 90)
        XCTAssertEqual(block.reason, "biggest rock")
    }

    func testNewSuggestionWithoutTaskIDHasNoLinkAnchors() {
        let entry = PlanDraftEntry(title: "Inbox zero", taskID: nil, minutes: 30)

        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "h",
            draft: [entry], liveTasks: [])

        let block = schedule.blocks[0]
        XCTAssertNil(block.originalID)
        XCTAssertNil(block.sectionDate)
        XCTAssertEqual(block.normalizedTitle, TitleSimilarity.normalize("Inbox zero"))
    }

    func testOrderPreservedAndStartTimesStackFromDraft() {
        let entries = [
            PlanDraftEntry(title: "A", taskID: nil, minutes: 60),
            PlanDraftEntry(title: "B", taskID: nil, minutes: 30),
        ]

        let schedule = DaySchedule(
            date: "d", startTime: start, sourceFileHash: "h",
            draft: entries, liveTasks: [])

        XCTAssertEqual(schedule.blocks.map(\.title), ["A", "B"])
        XCTAssertEqual(schedule.startTimes(), [start, start.addingTimeInterval(3600)])
    }
}
