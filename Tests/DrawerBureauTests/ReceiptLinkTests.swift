import DrawerCore
import XCTest
@testable import DrawerBureau

final class ReceiptLinkTests: XCTestCase {
    private func item(_ title: String, done: Bool = false) -> TodoItem {
        TodoItem(rawLine: "- [ ] \(title)", title: title, isDone: done, minutes: 25, sectionDate: "2026-07-13")
    }

    func testExactTitleRelinks() {
        var link = ReceiptLink(textSnapshot: "Call the landlord", sectionDate: "2026-07-13", state: .inDrawer)
        let match = link.relink(against: [item("Call the landlord")])
        XCTAssertEqual(match?.title, "Call the landlord")
        XCTAssertEqual(link.state, .inDrawer, "an exact match must not orphan the receipt")
    }

    func testCloseRenameStillRelinks() {
        var link = ReceiptLink(textSnapshot: "Call the landlord", sectionDate: "2026-07-13", state: .sticky)
        let match = link.relink(against: [item("Call the landlord about the lease")])
        XCTAssertEqual(match?.title, "Call the landlord about the lease")
        XCTAssertEqual(link.state, .sticky)
        XCTAssertEqual(link.textSnapshot, "Call the landlord about the lease", "textSnapshot refreshes on match")
    }

    func testUnrelatedTitleExpires() {
        var link = ReceiptLink(textSnapshot: "Call the landlord", sectionDate: "2026-07-13", state: .sticky)
        let match = link.relink(against: [item("Refactor the login flow")])
        XCTAssertNil(match)
        XCTAssertEqual(link.state, .expired)
    }

    func testNoItemsExpires() {
        var link = ReceiptLink(textSnapshot: "Call the landlord", sectionDate: "2026-07-13", state: .queued)
        XCTAssertNil(link.relink(against: []))
        XCTAssertEqual(link.state, .expired)
    }

    func testPicksTheBestScoringCandidateAmongSeveral() {
        var link = ReceiptLink(textSnapshot: "Fix the parser bug", sectionDate: "2026-07-13")
        let match = link.relink(against: [
            item("Refactor the login flow"),
            item("Fix parser bug in TodoParser"),
            item("Buy groceries"),
        ])
        XCTAssertEqual(match?.title, "Fix parser bug in TodoParser")
    }

    func testRelinkThresholdIsConservative() {
        // Documents the conservative bar: it must sit above the 0.5 line the
        // attribution classifier uses elsewhere, so a receipt never
        // silently jumps to a loosely-related task.
        XCTAssertGreaterThan(ReceiptLink.relinkThreshold, 0.5)
    }
}
