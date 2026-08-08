import XCTest

@testable import DrawerCore

/// Category-level edits: colour, delete, and reorder. Each one rewrites
/// headings or moves whole blocks, so every case checks the ideas came along.
final class ParkingLotBayTests: XCTestCase {
    private let text = """
    ## Apps
    - Widget (2026-07-19)

    ## Hardware (blue)
    - Macropad (2026-05-11)
        Cherry browns.

    ## Later
    - Someday
    """

    func testHeadingColorParses() {
        let doc = ParkingLotParser.parse(text)
        XCTAssertEqual(doc.bays.map(\.name), ["Apps", "Hardware", "Later"])
        XCTAssertNil(doc.bays[0].color)
        XCTAssertEqual(doc.bays[1].color, "blue")
    }

    func testHeadingParenThatIsNotAColorStaysInTheName() {
        let doc = ParkingLotParser.parse("## Money track (B2B)\n- Idea")
        XCTAssertEqual(doc.bays[0].name, "Money track (B2B)")
        XCTAssertNil(doc.bays[0].color)
    }

    func testSetAndClearBayColor() {
        let painted = ParkingLotWriteback.setBayColor(at: 0, to: "green", in: text)
        XCTAssertEqual(ParkingLotParser.parse(painted).bays[0].color, "green")
        XCTAssertEqual(ParkingLotParser.parse(painted).bays[0].name, "Apps")

        let cleared = ParkingLotWriteback.setBayColor(at: 1, to: nil, in: text)
        XCTAssertNil(ParkingLotParser.parse(cleared).bays[1].color)
        XCTAssertEqual(ParkingLotParser.parse(cleared).bays[1].ideas.count, 1)
    }

    func testRenameKeepsTheColor() {
        let out = ParkingLotWriteback.renameBay(at: 1, to: "Gear", in: text)
        let bay = ParkingLotParser.parse(out).bays[1]
        XCTAssertEqual(bay.name, "Gear")
        XCTAssertEqual(bay.color, "blue")
    }

    func testAppendFindsAColouredBay() {
        let out = ParkingLotWriteback.append(
            title: "Split keyboard", details: "", parked: "2026-08-07", color: nil,
            toBay: "Hardware", in: text)
        let doc = ParkingLotParser.parse(out)
        XCTAssertEqual(doc.bays.count, 3)
        XCTAssertEqual(doc.bays[1].ideas.map(\.title), ["Macropad", "Split keyboard"])
    }

    func testDeleteBayTakesItsIdeas() {
        let out = ParkingLotWriteback.deleteBay(at: 1, in: text)
        let doc = ParkingLotParser.parse(out)
        XCTAssertEqual(doc.bays.map(\.name), ["Apps", "Later"])
        XCTAssertFalse(out.contains("Macropad"))
        XCTAssertTrue(out.contains("Widget"))
        XCTAssertTrue(out.contains("Someday"))
    }

    func testMoveBayToTopAndBottom() {
        let up = ParkingLotParser.parse(ParkingLotWriteback.moveBay(from: 2, to: 0, in: text))
        XCTAssertEqual(up.bays.map(\.name), ["Later", "Apps", "Hardware"])

        let down = ParkingLotParser.parse(ParkingLotWriteback.moveBay(from: 0, to: 2, in: text))
        XCTAssertEqual(down.bays.map(\.name), ["Hardware", "Later", "Apps"])
    }

    func testMoveBayCarriesIdeasAndColor() {
        let doc = ParkingLotParser.parse(ParkingLotWriteback.moveBay(from: 1, to: 0, in: text))
        XCTAssertEqual(doc.bays[0].name, "Hardware")
        XCTAssertEqual(doc.bays[0].color, "blue")
        XCTAssertEqual(doc.bays[0].ideas[0].title, "Macropad")
        XCTAssertEqual(doc.bays[0].ideas[0].details, "Cherry browns.")
        XCTAssertEqual(doc.bays[1].ideas[0].title, "Widget")
    }

    func testMoveToBottomKeepsABlankLineBetweenBays() {
        let out = ParkingLotWriteback.moveBay(from: 0, to: 1, in: "## A\n- one\n\n## B\n- two")
        XCTAssertEqual(out, "## B\n- two\n\n## A\n- one\n")
        XCTAssertEqual(ParkingLotParser.parse(out).bays.map(\.name), ["B", "A"])
    }

    func testTitleWithANewlineStaysOneBullet() {
        let lines = ParkingLotWriteback.serialize(
            title: "First line\nsecond line", details: "", parked: nil, color: nil)
        XCTAssertEqual(lines, ["- First line second line"])
    }

    func testMoveBayOutOfRangeLeavesTextAlone() {
        XCTAssertEqual(ParkingLotWriteback.moveBay(from: 0, to: 9, in: text), text)
        XCTAssertEqual(ParkingLotWriteback.moveBay(from: 1, to: 1, in: text), text)
    }
}

@MainActor
final class ParkingLotStoreBayTests: XCTestCase {
    private final class Disk {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private func makeStore(_ initial: String) -> (ParkingLotStore, Disk) {
        let disk = Disk(initial)
        let store = ParkingLotStore(
            fileURL: URL(fileURLWithPath: "/tmp/parking-lot-bay-test.md"),
            debounce: 0,
            readString: { _ in disk.value },
            writeString: { value, _ in disk.value = value },
            todayProvider: { "2026-08-07" }
        )
        store.load()
        return (store, disk)
    }

    func testSetBayColorThenParkKeepsOneBay() {
        let (store, disk) = makeStore("## Apps\n- Widget\n")
        store.setBayColor(index: 0, to: "purple")
        XCTAssertEqual(store.document.bays[0].color, "purple")
        store.park(title: "Second", details: "", toBay: "Apps")
        XCTAssertEqual(store.document.bays.count, 1)
        XCTAssertEqual(store.document.bays[0].ideas.count, 2)
        store.saveNow()
        XCTAssertTrue(disk.value.hasPrefix("## Apps (purple)"))
    }

    func testDeleteBayRemovesItAndItsIdeas() {
        let (store, _) = makeStore("## Apps\n- Widget\n\n## Later\n- Someday\n")
        store.deleteBay(index: 0)
        XCTAssertEqual(store.document.bays.map(\.name), ["Later"])
        XCTAssertEqual(store.ideaCount, 1)
    }

    func testMoveBayReorders() {
        let (store, _) = makeStore("## A\n- one\n\n## B\n- two\n\n## C\n- three\n")
        store.moveBay(from: 2, to: 0)
        XCTAssertEqual(store.document.bays.map(\.name), ["C", "A", "B"])
    }

    func testAddBayIgnoresBlankAndDuplicateNames() {
        let (store, _) = makeStore("## Apps\n- Widget\n")
        store.addBay(named: "  ")
        store.addBay(named: "Apps")
        XCTAssertEqual(store.document.bays.count, 1)
        store.addBay(named: "Hardware")
        XCTAssertEqual(store.document.bays.map(\.name), ["Apps", "Hardware"])
    }
}
