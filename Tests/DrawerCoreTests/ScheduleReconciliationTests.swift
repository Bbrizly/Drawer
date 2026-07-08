import XCTest
@testable import DrawerCore

final class ScheduleReconciliationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    private func liveTask(_ title: String, date: String = "2026-07-06") -> TodoItem {
        TodoItem(rawLine: "- [ ] " + title, title: title, isDone: false, minutes: 25, sectionDate: date)
    }

    private func block(_ title: String, _ minutes: Int, id: String?) -> ScheduleBlock {
        ScheduleBlock(
            title: title, minutes: minutes, normalizedTitle: TitleSimilarity.normalize(title),
            originalID: id, sectionDate: "2026-07-06")
    }

    func testUnchangedFileLinksEveryBlockByID() {
        let ship = liveTask("Ship v2")
        let review = liveTask("Review PR")
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "H",
            blocks: [block("Ship v2", 90, id: ship.id), block("Review PR", 30, id: review.id)])
        let resolved = schedule.reconciled(against: [ship, review], currentHash: "H")

        XCTAssertFalse(resolved.needsReview)
        XCTAssertEqual(resolved.blocks.map(\.link),
                       [.linked(taskID: ship.id), .linked(taskID: review.id)])
        XCTAssertEqual(resolved.blocks.map(\.start), [start, start.addingTimeInterval(90 * 60)])
    }

    func testDriftedFileRelinksByNormalizedTitleAndFlags() {
        // File edited: the task's rawLine changed, so its id no longer matches
        // the stored originalID, but the title is the same.
        let ship = liveTask("Ship v2")
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "OLD",
            blocks: [block("Ship v2", 90, id: "2026-07-06|0|- [ ] Ship v2 (60m)")])
        let resolved = schedule.reconciled(against: [ship], currentHash: "NEW")

        XCTAssertTrue(resolved.needsReview)
        XCTAssertEqual(resolved.blocks.map(\.link), [.linked(taskID: ship.id)])
    }

    func testUnmatchedBlockDegradesToPlainAgendaItem() {
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "OLD",
            blocks: [block("Deleted task", 45, id: "gone")])
        let resolved = schedule.reconciled(against: [], currentHash: "NEW")

        XCTAssertTrue(resolved.needsReview)
        XCTAssertEqual(resolved.blocks.count, 1)
        XCTAssertEqual(resolved.blocks[0].link, .unlinked)
        XCTAssertEqual(resolved.blocks[0].block.title, "Deleted task")
        XCTAssertEqual(resolved.blocks[0].start, start)
    }

    func testTitleMatchIsOneToOne() {
        // Two blocks share a title but only one live task exists: exactly one links.
        let dup = liveTask("Email")
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "OLD",
            blocks: [block("Email", 15, id: "a"), block("Email", 15, id: "b")])
        let resolved = schedule.reconciled(against: [dup], currentHash: "NEW")

        let links = resolved.blocks.map(\.link)
        XCTAssertEqual(links.filter { $0 == .linked(taskID: dup.id) }.count, 1)
        XCTAssertEqual(links.filter { $0 == .unlinked }.count, 1)
    }

    func testTitleFallbackWontLinkAcrossSections() {
        // A same-title task from a different section must not be claimed: the
        // block is for 2026-07-06 Email, the only live Email is a backlog one.
        let backlogEmail = liveTask("Email", date: "2026-06-01")
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "OLD",
            blocks: [block("Email", 15, id: "gone")])
        let resolved = schedule.reconciled(against: [backlogEmail], currentHash: "NEW")
        XCTAssertEqual(resolved.blocks[0].link, .unlinked)
    }

    func testTitleFallbackLinksWithinSameSection() {
        let email = liveTask("Email", date: "2026-07-06")
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "OLD",
            blocks: [block("Email", 15, id: "gone")])
        let resolved = schedule.reconciled(against: [email], currentHash: "NEW")
        XCTAssertEqual(resolved.blocks[0].link, .linked(taskID: email.id))
    }

    func testNewSuggestionBlockNeverLinks() {
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "H",
            blocks: [block("Brand new idea", 20, id: nil)])
        let resolved = schedule.reconciled(against: [liveTask("Brand new idea")], currentHash: "H")

        // A nil-id block is a fresh suggestion, not a file task: agenda only.
        XCTAssertEqual(resolved.blocks[0].link, .unlinked)
    }
}
