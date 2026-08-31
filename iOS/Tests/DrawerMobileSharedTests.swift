import DrawerCore
import XCTest
@testable import DrawerMobile

final class DrawerMobileSharedTests: XCTestCase {
    private enum TestError: Error { case failed }

    override func tearDown() {
        DrawerFocusStore.clear()
        WidgetInteractionFeedbackStore.clear()
        super.tearDown()
    }

    func testWidgetSnapshotMatchesDrawerDisplayRules() throws {
        let data = """
        ## 2026-08-27
        - [ ] Carried
        - [x] Old done

        ## 2026-08-28
        - [/] Active (45m)
        - [ ] Today
        - [x] Finished

        ## 2026-08-29
        - [ ] Tomorrow

        ## Backlog
        - [ ] Later
        """.data(using: .utf8)!

        let snapshot = WidgetSnapshot.make(from: data, todayKey: "2026-08-28")

        XCTAssertEqual(snapshot.carried.map(\.title), ["Carried"])
        XCTAssertEqual(snapshot.today.map(\.title), ["Active", "Today", "Finished"])
        XCTAssertEqual(snapshot.upcoming.map(\.title), ["Tomorrow"])
        XCTAssertEqual(snapshot.backlog.map(\.title), ["Later"])
        XCTAssertEqual(snapshot.remaining, 3)
        XCTAssertEqual(snapshot.upcomingLabel, "Tomorrow")
    }

    func testWidgetSnapshotRoundTrips() throws {
        let data = "## 2026-08-28\n- [ ] One\n".data(using: .utf8)!
        let snapshot = WidgetSnapshot.make(from: data, todayKey: "2026-08-28")
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snapshot)
    }

    func testWidgetInteractionFailureIsShortLived() {
        let before = Date()
        WidgetInteractionFeedbackStore.recordFailure(TestError.failed)

        let visible = WidgetInteractionFeedbackStore.current(now: before.addingTimeInterval(1))
        XCTAssertEqual(visible?.message, "Update failed. Open Drawer and try again.")

        XCTAssertNil(
            WidgetInteractionFeedbackStore.current(now: before.addingTimeInterval(6 * 60))
        )
    }

    func testObsidianLinkStripsAlias() {
        let link = ObsidianLink.first(in: "Finish [[QCM Mobile|the mobile plan]] today")
        XCTAssertEqual(link?.note, "QCM Mobile")
    }

    func testDrawerDateAdvancesLeapDayAndRejectsImpossibleDates() {
        XCTAssertEqual(DrawerDate.dayAfter("2028-02-28"), "2028-02-29")
        XCTAssertEqual(DrawerDate.dayAfter("2028-02-29"), "2028-03-01")
        XCTAssertNil(DrawerDate.dayAfter("2027-02-29"))
        XCTAssertNil(DrawerDate.dayAfter("not-a-date"))
    }

    func testPersistedFocusRoundTripsThroughSharedStore() {
        let focus = DrawerPersistedFocus(
            id: UUID(),
            taskTitle: "Ship Drawer",
            phase: .paused,
            endDate: nil,
            remaining: 321,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        DrawerFocusStore.save(focus)
        XCTAssertEqual(DrawerFocusStore.load(), focus)

        DrawerFocusStore.clear()
        XCTAssertNil(DrawerFocusStore.load())
    }
}
