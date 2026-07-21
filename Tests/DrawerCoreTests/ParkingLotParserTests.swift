import XCTest

@testable import DrawerCore

final class ParkingLotParserTests: XCTestCase {
    func testParsesBaysIdeasAndDetails() {
        let text = """
        ## Apps
        - Lock screen widget (2026-07-19 yellow)
            A tiny glanceable version.
            Just the next task.
        - Pluck for Instagram (2026-03-02 pink)

        ## Hardware
        - Build a macropad (2026-05-11 blue)
        """
        let doc = ParkingLotParser.parse(text)
        XCTAssertEqual(doc.bays.map(\.name), ["Apps", "Hardware"])
        XCTAssertEqual(doc.bays[0].ideas.count, 2)
        let first = doc.bays[0].ideas[0]
        XCTAssertEqual(first.title, "Lock screen widget")
        XCTAssertEqual(first.parked, "2026-07-19")
        XCTAssertEqual(first.color, "yellow")
        XCTAssertEqual(first.details, "A tiny glanceable version.\nJust the next task.")
        XCTAssertEqual(first.lineRange, 1..<4)
        XCTAssertEqual(doc.bays[1].ideas[0].title, "Build a macropad")
    }

    func testMetadataVariants() {
        let doc = ParkingLotParser.parse("""
        ## Bay
        - Date only (2026-01-02)
        - Color only (pink)
        - Reversed (pink 2026-01-02)
        - Neither
        - Junk (soon)
        - Bad date (2026-13-99)
        """)
        let i = doc.bays[0].ideas
        XCTAssertEqual(i[0].parked, "2026-01-02")
        XCTAssertNil(i[0].color)
        XCTAssertEqual(i[1].color, "pink")
        XCTAssertNil(i[1].parked)
        XCTAssertEqual(i[2].color, "pink")
        XCTAssertEqual(i[2].parked, "2026-01-02")
        XCTAssertNil(i[3].parked)
        XCTAssertNil(i[3].color)
        XCTAssertEqual(i[3].title, "Neither")
        XCTAssertEqual(i[4].title, "Junk (soon)")
        XCTAssertEqual(i[5].title, "Bad date (2026-13-99)")
    }

    func testDetailsStopAtBlankLine() {
        let doc = ParkingLotParser.parse("""
        ## Bay
        - Idea
            first
            second

            stray indented prose
        - Next
        """)
        XCTAssertEqual(doc.bays[0].ideas[0].details, "first\nsecond")
        XCTAssertEqual(doc.bays[0].ideas.count, 2)
    }

    func testIgnoresLinesOutsideBays() {
        let doc = ParkingLotParser.parse("- Orphan idea\nprose\n## Bay\n- Real")
        XCTAssertEqual(doc.bays.count, 1)
        XCTAssertEqual(doc.bays[0].ideas.map(\.title), ["Real"])
    }

    func testColumnsChunking() {
        XCTAssertEqual(ParkingLotLayout.rows(ideas: 7, perRow: 3), 3)
        // Exactly full takes no extra row: 23 bays of reserved empties cost a
        // third of the lot's height.
        XCTAssertEqual(ParkingLotLayout.rows(ideas: 6, perRow: 3), 2)
        // An empty bay still paints one row, so it reads as a bay.
        XCTAssertEqual(ParkingLotLayout.rows(ideas: 0, perRow: 3), 1)
        XCTAssertEqual(ParkingLotLayout.rows(ideas: 2, perRow: 0), 1)
    }
}
