import XCTest
@testable import DrawerBureau

/// The panel the manager sizes a sticky window to. The bullet block grows the
/// note, so the count of rows the layout actually draws and the count the
/// metrics charge for have to stay the same number.
@MainActor
final class StickyMetricsTests: XCTestCase {
    private func model(
        _ size: StickySize,
        subtasks: [String] = [],
        cap: Int = 6,
        expanded: Bool = false
    ) -> StickyModel {
        let m = StickyModel(receiptID: UUID(), title: "Call the landlord", size: size)
        m.subtasks = subtasks
        m.subtaskVisibleCap = cap
        m.pullOutScale = 1.5
        m.slipSize = StickyMetrics.drawerSlip
        if expanded { m.isExpanded = true }
        return m
    }

    private var base: CGFloat {
        StickyMetrics.size(.full, pullOutScale: 1.5, slip: StickyMetrics.drawerSlip).height
    }

    /// The "Add a point" row renders even with nothing in the note, so an
    /// unbulleted sticky is still one row taller than the bare slip.
    func testEmptyNoteStillPaysForTheAddRow() {
        let size = StickyMetrics.size(for: model(.full))
        XCTAssertEqual(size.height, base + StickyMetrics.subtaskRowHeight)
    }

    func testEachVisibleBulletAddsARow() {
        let size = StickyMetrics.size(for: model(.full, subtasks: ["a", "b", "c"]))
        XCTAssertEqual(size.height, base + 4 * StickyMetrics.subtaskRowHeight)
    }

    /// Past the cap the note stops growing and buys one "+N more" row instead.
    func testOverflowBuysExactlyOneExtraRow() {
        let m = model(.full, subtasks: (1...10).map(String.init), cap: 6)
        XCTAssertEqual(m.visibleSubtaskCount, 6)
        XCTAssertEqual(m.overflowCount, 4)
        // 6 visible + 1 overflow + 1 add
        XCTAssertEqual(StickyMetrics.size(for: m).height, base + 8 * StickyMetrics.subtaskRowHeight)
    }

    func testExpandedShowsEveryBulletAndDropsTheOverflowRow() {
        let m = model(.full, subtasks: (1...10).map(String.init), cap: 6, expanded: true)
        XCTAssertEqual(m.overflowCount, 0)
        // 10 visible + 1 add
        XCTAssertEqual(StickyMetrics.size(for: m).height, base + 11 * StickyMetrics.subtaskRowHeight)
    }

    /// Only the pull-out lists bullets, so the small sizes stay fixed no matter
    /// how long the note is.
    func testSmallSizesIgnoreSubtasks() {
        for size in [StickySize.title, .chip] {
            let bare = StickyMetrics.size(for: model(size))
            let full = StickyMetrics.size(for: model(size, subtasks: (1...10).map(String.init)))
            XCTAssertEqual(bare, full, "\(size) should not grow")
            XCTAssertEqual(bare, StickyMetrics.size(size, slip: StickyMetrics.drawerSlip))
        }
    }

    func testPullOutScalesTheSlip() {
        let m = model(.full)
        m.pullOutScale = 2
        let size = StickyMetrics.size(for: m)
        XCTAssertEqual(size.width, StickyMetrics.drawerSlip.width * 2)
        XCTAssertEqual(
            size.height,
            StickyMetrics.drawerSlip.height * 2 + StickyMetrics.subtaskRowHeight
        )
    }
}
