import DrawerCore
import XCTest
@testable import DrawerMobile

final class DrawerMobileSharedTests: XCTestCase {
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

    func testObsidianLinkStripsAlias() {
        let link = ObsidianLink.first(in: "Finish [[QCM Mobile|the mobile plan]] today")
        XCTAssertEqual(link?.note, "QCM Mobile")
    }
}
