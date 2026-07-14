import XCTest
@testable import DrawerBureau

/// The cap / oldest-retire rule (spec "Pull-out": cap 12, #13 sends the oldest
/// home) lives in `StickyRoster` as a plain value type, so it is tested here
/// with no display and no `NSPanel`. `StickyPanelManagerTests` then checks that
/// the manager acts on these decisions (closes the panel, marks the store).
final class StickyRosterTests: XCTestCase {
    func testInsertUnderCapRetiresNothing() {
        var roster = StickyRoster()
        let a = UUID(), b = UUID()
        XCTAssertNil(roster.insert(a, cap: 3))
        XCTAssertNil(roster.insert(b, cap: 3))
        XCTAssertEqual(roster.count, 2)
        XCTAssertEqual(roster.oldest, a)
    }

    func testInsertPastCapRetiresOldest() {
        var roster = StickyRoster()
        let a = UUID(), b = UUID(), c = UUID()
        roster.insert(a, cap: 2)
        roster.insert(b, cap: 2)
        let retired = roster.insert(c, cap: 2)
        XCTAssertEqual(retired, a)
        XCTAssertEqual(roster.count, 2)
        XCTAssertFalse(roster.contains(a))
        XCTAssertTrue(roster.contains(b))
        XCTAssertTrue(roster.contains(c))
    }

    /// Re-inserting a live id makes it the newest, so it is no longer next to be
    /// retired: touching a sticky keeps it around.
    func testReinsertMovesToNewest() {
        var roster = StickyRoster()
        let a = UUID(), b = UUID(), c = UUID()
        roster.insert(a, cap: 2)
        roster.insert(b, cap: 2)
        roster.insert(a, cap: 2) // a is touched again, now newest; b is oldest
        let retired = roster.insert(c, cap: 2)
        XCTAssertEqual(retired, b)
        XCTAssertTrue(roster.contains(a))
        XCTAssertTrue(roster.contains(c))
    }

    func testRemoveDropsFromOrder() {
        var roster = StickyRoster()
        let a = UUID(), b = UUID()
        roster.insert(a, cap: 5)
        roster.insert(b, cap: 5)
        roster.remove(a)
        XCTAssertFalse(roster.contains(a))
        XCTAssertEqual(roster.oldest, b)
        XCTAssertEqual(roster.count, 1)
    }

    /// The twelve/thirteen headline case, straight from the spec.
    func testTwelveCapSendsTheThirteenthsOldestHome() {
        var roster = StickyRoster()
        let ids = (0..<12).map { _ in UUID() }
        for id in ids { XCTAssertNil(roster.insert(id, cap: 12)) }
        let thirteenth = UUID()
        XCTAssertEqual(roster.insert(thirteenth, cap: 12), ids.first)
        XCTAssertEqual(roster.count, 12)
    }

    /// A cap of zero is treated as one, never negative, so a spawn always leaves
    /// at least the note just opened.
    func testCapIsClampedToAtLeastOne() {
        var roster = StickyRoster()
        let a = UUID(), b = UUID()
        roster.insert(a, cap: 0)
        let retired = roster.insert(b, cap: 0)
        XCTAssertEqual(retired, a)
        XCTAssertEqual(roster.count, 1)
        XCTAssertTrue(roster.contains(b))
    }
}
