import XCTest
@testable import Drawer

/// Bay headings in the real file read "2026-07-18: B2B money track (aside)".
/// The sign has to show the category, not the date and not the aside.
final class BaySignTests: XCTestCase {
    func testSplitsDateFromCategory() {
        let sign = ParkingLotView.baySign("2026-07-18: B2B money track (5 rounds)")
        XCTAssertEqual(sign.date, "2026-07-18")
        XCTAssertEqual(sign.category, "B2B money track (5 rounds)")
    }

    func testUndatedHeadingKeepsItsWholeName() {
        let sign = ParkingLotView.baySign("Unsorted")
        XCTAssertNil(sign.date)
        XCTAssertEqual(sign.category, "Unsorted")
    }

    func testColonInCategoryIsNotMistakenForADate() {
        let sign = ParkingLotView.baySign("Games: roguelikes")
        XCTAssertNil(sign.date)
        XCTAssertEqual(sign.category, "Games: roguelikes")
    }

    func testSignDropsTrailingAside() {
        XCTAssertEqual(
            ParkingLotView.signCategory("OMI fork + Obsidian (combined desktop app)"),
            "OMI fork + Obsidian")
    }

    func testSignKeepsAnAsideThatIsTheWholeName() {
        XCTAssertEqual(ParkingLotView.signCategory("(untitled)"), "(untitled)")
    }
}
