import DrawerCore
import Foundation
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

    func testWidgetExplainsICloudMaterializationWithoutChangingTruth() {
        let before = Date()
        WidgetInteractionFeedbackStore.recordFailure(DrawerFileAccessError.waitingForICloud)

        let visible = WidgetInteractionFeedbackStore.current(now: before.addingTimeInterval(1))
        XCTAssertEqual(
            visible?.message,
            "Drawer.md is syncing from iCloud. Open Drawer to finish syncing, then retry."
        )
    }

    func testICloudStaleAndEvictedStatesRequireMaterialization() {
        XCTAssertTrue(DrawerFileSession.iCloudNeedsMaterialization(.notDownloaded))
        XCTAssertTrue(DrawerFileSession.iCloudNeedsMaterialization(.downloaded))
        XCTAssertFalse(DrawerFileSession.iCloudNeedsMaterialization(.current))
        XCTAssertFalse(DrawerFileSession.iCloudNeedsMaterialization(nil))
    }

    func testPlainLocalFileSessionReadsAndWritesWithoutSecurityScope() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Drawer.md")
        let original = "## 2026-08-31\n- [ ] Local\n".data(using: .utf8)!
        let updated = "## 2026-08-31\n- [x] Local\n".data(using: .utf8)!
        try original.write(to: url)

        let session = DrawerFileSession(url: url)
        XCTAssertEqual(session.storageKind, .files)
        XCTAssertEqual(try session.read(), original)

        try session.write(updated)
        XCTAssertEqual(try Data(contentsOf: url), updated)
        XCTAssertEqual(try session.read(), updated)
    }

    func testProviderErrorsDistinguishAutomaticRetryFromGrantPreservation() {
        let unavailable = DrawerFileAccessError.providerUnavailable(.files)
        XCTAssertTrue(unavailable.isTransient)
        XCTAssertTrue(unavailable.preservesSelectedGrant)
        XCTAssertEqual(
            unavailable.widgetMessage,
            "Drawer.md's Files provider is unavailable. Open Drawer to retry."
        )

        let authentication = DrawerFileAccessError.authenticationRequired(.files)
        XCTAssertFalse(authentication.isTransient)
        XCTAssertTrue(authentication.preservesSelectedGrant)

        let conflict = DrawerFileAccessError.iCloudConflict
        XCTAssertFalse(conflict.isTransient)
        XCTAssertTrue(conflict.preservesSelectedGrant)

        let permission = DrawerFileAccessError.permissionDenied
        XCTAssertFalse(permission.isTransient)
        XCTAssertFalse(permission.preservesSelectedGrant)
        XCTAssertEqual(permission.widgetMessage, "Open Drawer to reconnect Drawer.md.")

        let missing = DrawerFileAccessError.itemMissing
        XCTAssertFalse(missing.isTransient)
        XCTAssertFalse(missing.preservesSelectedGrant)
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
