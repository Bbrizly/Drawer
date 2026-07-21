import XCTest

@testable import DrawerCore

@MainActor
final class ParkingLotStoreTests: XCTestCase {
    private final class Disk {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private func makeStore(initial: String) -> (ParkingLotStore, Disk) {
        let disk = Disk(initial)
        let store = ParkingLotStore(
            fileURL: URL(fileURLWithPath: "/tmp/parking-lot-test.md"),
            debounce: 0,
            readString: { _ in disk.value },
            writeString: { value, _ in disk.value = value },
            todayProvider: { "2026-07-19" }
        )
        return (store, disk)
    }

    private let canonical = """
    ## Apps
    - Lock screen widget (2026-07-19 yellow)
        A tiny glanceable version.

    ## Hardware
    - Build a macropad (2026-05-11 blue)
    """

    func testLoadParsesFile() {
        let (store, _) = makeStore(initial: canonical)
        store.load()
        XCTAssertEqual(store.document.bays.map(\.name), ["Apps", "Hardware"])
        XCTAssertEqual(store.ideaCount, 2)
    }

    func testUpdateReparsesAndWrites() {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.update(bayIndex: 0, ideaIndex: 0,
                     title: "Lock widget", details: "Smaller scope.", color: "pink")
        XCTAssertEqual(store.document.bays[0].ideas[0].title, "Lock widget")
        store.saveNow()
        XCTAssertTrue(disk.value.contains("- Lock widget (2026-07-19 pink)\n    Smaller scope."))
        XCTAssertTrue(disk.value.contains("- Build a macropad (2026-05-11 blue)"))
    }

    func testParkCreatesUnsortedWithToday() {
        let (store, disk) = makeStore(initial: "")
        store.load()
        store.park(title: "Wild thought", details: "Maybe.")
        store.saveNow()
        XCTAssertTrue(disk.value.hasPrefix("## Unsorted\n- Wild thought (2026-07-19)\n    Maybe."))
        XCTAssertEqual(store.document.bays[0].name, "Unsorted")
    }

    func testParkEmptyTitleIntoNamedBay() {
        let (store, _) = makeStore(initial: canonical)
        store.load()
        store.park(title: "", details: "", toBay: "Hardware")
        let bay = store.document.bays.first { $0.name == "Hardware" }
        XCTAssertEqual(bay?.ideas.count, 2)
        XCTAssertEqual(bay?.ideas.last?.title, "")
        XCTAssertEqual(bay?.ideas.last?.parked, "2026-07-19")
    }

    func testOutsideEditIsNotClobberedByAPendingSave() async {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.update(bayIndex: 0, ideaIndex: 0,
                     title: "Renamed", details: "", color: nil)
        // Someone rewrites the whole file (Obsidian, a script) before our
        // debounced write lands. Their version must survive.
        disk.value = "## Apps\n- Someone else rewrote the file\n"
        store.saveNow()
        XCTAssertTrue(disk.value.contains("Someone else rewrote the file"))
        XCTAssertFalse(disk.value.contains("Renamed"))
    }

    func testDeleteRemovesIdea() {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.delete(bayIndex: 0, ideaIndex: 0)
        store.saveNow()
        XCTAssertFalse(disk.value.contains("Lock screen widget"))
        XCTAssertEqual(store.ideaCount, 1)
    }

    func testExternalReloadSkippedWhileSavePending() {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.update(bayIndex: 0, ideaIndex: 0,
                     title: "Renamed", details: "", color: nil)
        // An outside edit lands while our save is still debouncing.
        disk.value = "## Apps\n- Someone else wrote this\n"
        store.load()
        // A stale read must not wipe what you just typed in the app,
        XCTAssertEqual(store.document.bays[0].ideas[0].title, "Renamed")
        // but the save that follows must not wipe their file either.
        store.saveNow()
        XCTAssertTrue(disk.value.contains("- Someone else wrote this"))
        XCTAssertEqual(store.document.bays[0].ideas[0].title, "Someone else wrote this")
    }

    func testMoveKeepsMetadata() {
        let (store, _) = makeStore(initial: canonical)
        store.load()
        store.move(bayIndex: 0, ideaIndex: 0, toBay: "Hardware")
        let moved = store.document.bays.first { $0.name == "Hardware" }?.ideas.last
        XCTAssertEqual(moved?.title, "Lock screen widget")
        XCTAssertEqual(moved?.parked, "2026-07-19")
        XCTAssertEqual(moved?.color, "yellow")
        XCTAssertEqual(moved?.details, "A tiny glanceable version.")
        XCTAssertTrue(store.document.bays.first { $0.name == "Apps" }!.ideas.isEmpty)
    }
}
