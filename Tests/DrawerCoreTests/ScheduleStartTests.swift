import XCTest
@testable import DrawerCore

/// The default day-start seeded when a plan is accepted: now, rounded UP to the
/// next quarter hour so the first block begins on a clean :00/:15/:30/:45.
final class ScheduleStartTests: XCTestCase {
    private func ref(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    func testRoundsUpToNextQuarterHour() {
        // 10 minutes past the hour -> next quarter is :15.
        XCTAssertEqual(DaySchedule.defaultStart(now: ref(10 * 60)), ref(15 * 60))
    }

    func testExactQuarterHourStaysPut() {
        XCTAssertEqual(DaySchedule.defaultStart(now: ref(15 * 60)), ref(15 * 60))
    }

    func testOneSecondPastAQuarterRollsToTheNext() {
        XCTAssertEqual(DaySchedule.defaultStart(now: ref(15 * 60 + 1)), ref(30 * 60))
    }
}
