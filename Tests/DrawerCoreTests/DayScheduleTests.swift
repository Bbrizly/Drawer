import XCTest
@testable import DrawerCore

final class DayScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)  // stacking is duration math, wall time irrelevant

    private func block(_ title: String, _ minutes: Int) -> ScheduleBlock {
        ScheduleBlock(title: title, minutes: minutes, normalizedTitle: TitleSimilarity.normalize(title))
    }

    func testStartTimesStackDurations() {
        let schedule = DaySchedule(
            date: "2026-07-06", startTime: start, sourceFileHash: "h",
            blocks: [block("Ship v2", 90), block("Review PR", 30), block("Standup", 15)])
        let times = schedule.startTimes()
        XCTAssertEqual(times, [
            start,
            start.addingTimeInterval(90 * 60),
            start.addingTimeInterval(120 * 60),
        ])
    }

    func testStartTimesEmptyIsEmpty() {
        let schedule = DaySchedule(date: "2026-07-06", startTime: start, sourceFileHash: "h", blocks: [])
        XCTAssertEqual(schedule.startTimes(), [])
    }
}
