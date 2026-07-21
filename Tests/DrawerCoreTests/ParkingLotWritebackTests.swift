import XCTest

@testable import DrawerCore

final class ParkingLotWritebackTests: XCTestCase {
    let canonical = """
    Intro prose the parser ignores.

    ## Apps
    - Lock screen widget (2026-07-19 yellow)
        A tiny glanceable version.
    - Pluck for Instagram (2026-03-02 pink)

    ## Hardware
    - Build a macropad (2026-05-11 blue)
    """

    func testRoundTripIsByteIdentical() {
        var text = canonical
        // Re-serialise every idea in place with unchanged content. Reversed so
        // earlier line ranges stay valid while later ones are spliced.
        for bay in ParkingLotParser.parse(text).bays.reversed() {
            for idea in bay.ideas.reversed() {
                text = ParkingLotWriteback.replace(
                    idea, in: text,
                    title: idea.title, details: idea.details, color: idea.color)
            }
        }
        XCTAssertEqual(text, canonical)
    }

    func testEditSplicesOnlyThatIdea() {
        let doc = ParkingLotParser.parse(canonical)
        let out = ParkingLotWriteback.replace(
            doc.bays[0].ideas[1], in: canonical,
            title: "Pluck for IG", details: "Check the API first.", color: "blue")
        XCTAssertTrue(out.contains("Intro prose the parser ignores."))
        XCTAssertTrue(out.contains("- Pluck for IG (2026-03-02 blue)\n    Check the API first."))
        XCTAssertTrue(out.contains("- Lock screen widget (2026-07-19 yellow)"))
        XCTAssertTrue(out.contains("## Hardware"))
    }

    func testDeleteRemovesIdeaAndDetails() {
        let doc = ParkingLotParser.parse(canonical)
        let out = ParkingLotWriteback.delete(doc.bays[0].ideas[0], in: canonical)
        XCTAssertFalse(out.contains("Lock screen widget"))
        XCTAssertFalse(out.contains("glanceable"))
        XCTAssertTrue(out.contains("- Pluck for Instagram (2026-03-02 pink)"))
    }

    func testAppendToExistingBay() {
        let out = ParkingLotWriteback.append(
            title: "New idea", details: "", parked: "2026-07-19", color: nil,
            toBay: "Apps", in: canonical)
        let doc = ParkingLotParser.parse(out)
        XCTAssertEqual(doc.bays[0].ideas.last?.title, "New idea")
        XCTAssertEqual(doc.bays[1].ideas.count, 1)
    }

    func testAppendCreatesMissingBayAtTop() {
        let out = ParkingLotWriteback.append(
            title: "Loose", details: "", parked: "2026-07-19", color: nil,
            toBay: "Unsorted", in: canonical)
        XCTAssertTrue(out.hasPrefix("## Unsorted\n- Loose (2026-07-19)\n"))
        XCTAssertTrue(out.contains("Intro prose the parser ignores."))
    }

    func testSerializeWithoutMetadata() {
        XCTAssertEqual(
            ParkingLotWriteback.serialize(title: "Plain", details: "", parked: nil, color: nil),
            ["- Plain"])
    }
    func testRenameBayKeepsItsIdeas() {
        let out = ParkingLotWriteback.renameBay(at: 1, to: "Later", in: canonical)
        let doc = ParkingLotParser.parse(out)
        XCTAssertEqual(doc.bays[1].name, "Later")
        XCTAssertEqual(
            doc.bays[1].ideas.map(\.title),
            ParkingLotParser.parse(canonical).bays[1].ideas.map(\.title))
        XCTAssertEqual(doc.bays[0].name, ParkingLotParser.parse(canonical).bays[0].name)
    }

    func testRenameBayOutOfRangeLeavesTextAlone() {
        XCTAssertEqual(ParkingLotWriteback.renameBay(at: 99, to: "Nope", in: canonical), canonical)
    }
}
