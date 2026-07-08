import XCTest
@testable import DrawerCore

final class DayScheduleStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    // In-memory JSONL backing so the store never touches disk.
    private func memStore() -> (DayScheduleStore, () -> [String]) {
        final class Box: @unchecked Sendable { var lines: [String] = [] }
        let box = Box()
        let store = DayScheduleStore(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            read: { _ in box.lines.joined(separator: "\n") },
            appendLine: { line, _ in box.lines.append(line.trimmingCharacters(in: .newlines)) },
            overwrite: { text, _ in box.lines = text.split(separator: "\n").map(String.init) })
        return (store, { box.lines })
    }

    private func schedule(_ date: String, _ title: String) -> DaySchedule {
        DaySchedule(
            date: date, startTime: start, sourceFileHash: "H",
            blocks: [ScheduleBlock(title: title, minutes: 30, normalizedTitle: title.lowercased())])
    }

    func testSaveThenLatestRoundTrips() throws {
        let (store, _) = memStore()
        let s = schedule("2026-07-06", "Ship v2")
        try store.save(s)
        XCTAssertEqual(store.latest(for: "2026-07-06"), s)
    }

    func testLatestReturnsNewestForDate() throws {
        let (store, _) = memStore()
        try store.save(schedule("2026-07-06", "Old plan"))
        try store.save(schedule("2026-07-06", "New plan"))
        XCTAssertEqual(store.latest(for: "2026-07-06")?.blocks.first?.title, "New plan")
    }

    func testLatestMissingDateIsNil() {
        let (store, _) = memStore()
        XCTAssertNil(store.latest(for: "2026-07-06"))
    }
}
