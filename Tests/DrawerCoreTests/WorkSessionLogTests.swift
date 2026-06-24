import XCTest
@testable import DrawerCore

/// In-memory log: a `@Sendable` closure cannot capture a bare `var`, so the
/// text lives in a reference box.
final class LogBox: @unchecked Sendable { var text = "" }

func makeMemoryLog(_ box: LogBox) -> WorkSessionLog {
    WorkSessionLog(
        fileURL: URL(fileURLWithPath: "/dev/null"),
        read: { _ in box.text },
        appendLine: { line, _ in box.text += line },
        overwrite: { value, _ in box.text = value }
    )
}

private func dayString(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = Calendar.current.timeZone
    return f.string(from: date)
}

private func session(
    _ title: String, start: TimeInterval, length: TimeInterval
) -> WorkSession {
    let s = Date(timeIntervalSince1970: start)
    return WorkSession(taskID: title, taskTitle: title, start: s, end: s.addingTimeInterval(length))
}

final class WorkSessionLogTests: XCTestCase {
    func testAppendRoundTrips() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 100))
        try log.append(session("B", start: 200, length: 50))
        let all = log.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.map(\.taskTitle), ["A", "B"])
        XCTAssertEqual(all[0].seconds, 100, accuracy: 0.001)
    }

    func testAppendDropsSubSecond() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 0.4))
        XCTAssertEqual(log.all().count, 0)
    }

    func testTotalFiltersByTitleAndDay() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        // Two "A" sessions an hour apart (same local day), one "B".
        try log.append(session("A", start: 0, length: 100))
        try log.append(session("A", start: 3600, length: 50))
        try log.append(session("B", start: 0, length: 200))
        let day = dayString(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(log.total(forTitle: "A", on: day), 150, accuracy: 0.001)
        XCTAssertEqual(log.total(forTitle: "B", on: day), 200, accuracy: 0.001)
        XCTAssertEqual(log.total(forTitle: "A", on: "1999-01-01"), 0, accuracy: 0.001)
    }

    func testSummaryGroupsSortsTotals() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 100))
        try log.append(session("A", start: 3600, length: 50))
        try log.append(session("B", start: 0, length: 200))
        let day = dayString(Date(timeIntervalSince1970: 0))
        let summary = log.summary(for: day)
        XCTAssertEqual(summary.rows.map(\.taskTitle), ["B", "A"])   // longest first
        XCTAssertEqual(summary.rows.first?.seconds ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(summary.total, 350, accuracy: 0.001)
        XCTAssertEqual(summary.longest?.taskTitle, "B")
    }

    func testSummaryIgnoresOtherDays() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 100))
        try log.append(session("A", start: 2 * 86_400, length: 999))   // two days later
        let day = dayString(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(log.summary(for: day).total, 100, accuracy: 0.001)
    }

    func testReplaceAllDeletesByRewrite() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        let keep = session("A", start: 0, length: 100)
        try log.append(keep)
        try log.append(session("B", start: 200, length: 50))
        try log.replaceAll(log.all().filter { $0.taskTitle == "A" })
        XCTAssertEqual(log.all().map(\.taskTitle), ["A"])
    }

    func testSetTotalEditsAndDeletes() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 100))
        try log.append(session("A", start: 3600, length: 50))   // two A sessions, same day
        try log.append(session("B", start: 0, length: 200))
        let day = dayString(Date(timeIntervalSince1970: 0))
        // Edit A to 5 minutes: both A sessions collapse to one, B is untouched.
        try log.setTotal(forTitle: "A", on: day, seconds: 300)
        XCTAssertEqual(log.total(forTitle: "A", on: day), 300, accuracy: 0.001)
        XCTAssertEqual(log.total(forTitle: "B", on: day), 200, accuracy: 0.001)
        // Delete B.
        try log.setTotal(forTitle: "B", on: day, seconds: 0)
        XCTAssertEqual(log.total(forTitle: "B", on: day), 0, accuracy: 0.001)
        XCTAssertEqual(log.summary(for: day).rows.map(\.taskTitle), ["A"])
    }

    func testCorruptLineIsSkipped() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        try log.append(session("A", start: 0, length: 100))
        box.text = "this is not json\n" + box.text
        XCTAssertEqual(log.all().count, 1)
    }
}
