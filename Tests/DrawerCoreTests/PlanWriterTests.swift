import XCTest
@testable import DrawerCore

final class PlanWriterTests: XCTestCase {
    private func write(
        _ text: String,
        date: String,
        _ entries: [PlanEntry],
        replace: Bool = false
    ) throws -> String {
        let out = try PlanWriter.write(
            date: date, entries: entries, replace: replace, in: Data(text.utf8)
        )
        return String(data: out, encoding: .utf8)!
    }

    // MARK: create

    func testCreatesSectionInEmptyFile() throws {
        let out = try write("", date: "2026-07-06", [PlanEntry(title: "Write spec", minutes: 30)])
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] Write spec (30m)\n")
    }

    func testCreatesSectionInDateOrderBeforeLaterDay() throws {
        let out = try write(
            "## 2026-07-08\n- [ ] later task\n",
            date: "2026-07-06", [PlanEntry(title: "early")]
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] early\n\n## 2026-07-08\n- [ ] later task\n")
    }

    func testCreatesSectionBeforeBacklog() throws {
        let out = try write(
            "## 2026-07-06\n- [ ] a\n\n## Backlog\n- [ ] someday\n",
            date: "2026-07-07", [PlanEntry(title: "b")]
        )
        XCTAssertEqual(
            out,
            "## 2026-07-06\n- [ ] a\n\n## 2026-07-07\n- [ ] b\n\n## Backlog\n- [ ] someday\n"
        )
    }

    func testAppendsNewSectionAfterEarlierDays() throws {
        let out = try write(
            "## 2026-07-01\n- [ ] old\n",
            date: "2026-07-05", [PlanEntry(title: "new")]
        )
        XCTAssertEqual(out, "## 2026-07-01\n- [ ] old\n\n## 2026-07-05\n- [ ] new\n")
    }

    // MARK: merge

    func testAppendMergeSkipsDuplicateTitleKeepsExisting() throws {
        let out = try write(
            "## 2026-07-06\n- [ ] existing\n",
            date: "2026-07-06",
            [PlanEntry(title: "existing"), PlanEntry(title: "new one", minutes: 15)]
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] existing\n- [ ] new one (15m)\n")
    }

    func testReplaceRemovesUncheckedButNeverChecked() throws {
        let out = try write(
            "## 2026-07-06\n- [x] done thing\n- [ ] todo thing\n",
            date: "2026-07-06", [PlanEntry(title: "fresh")], replace: true
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [x] done thing\n- [ ] fresh\n")
    }

    func testReplaceLeavesInProgressAlone() throws {
        let out = try write(
            "## 2026-07-06\n- [/] working on it\n- [ ] queued\n",
            date: "2026-07-06", [PlanEntry(title: "planned")], replace: true
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [/] working on it\n- [ ] planned\n")
    }

    func testWritesNoteAsIndentedLine() throws {
        let out = try write(
            "", date: "2026-07-06",
            [PlanEntry(title: "task", note: "remember this")]
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] task\n    remember this\n")
    }

    func testTaskIDToBacklogItemWritesFreshLineOriginalStays() throws {
        let file = "## 2026-07-06\n- [ ] today thing\n\n## Backlog\n- [ ] ship it\n"
        // id = sectionDate|occurrence|rawLine
        let backlogID = "backlog|0|- [ ] ship it"
        let out = try write(
            file, date: "2026-07-06",
            [PlanEntry(title: "ship it", taskID: backlogID)]
        )
        XCTAssertEqual(
            out,
            "## 2026-07-06\n- [ ] today thing\n- [ ] ship it\n\n## Backlog\n- [ ] ship it\n"
        )
    }

    // MARK: validation

    func testRejectsEmptyPlan() {
        XCTAssertThrowsError(try write("", date: "2026-07-06", [])) {
            XCTAssertEqual($0 as? PlanWriterError, .emptyPlan)
        }
    }

    func testRejectsOverCount() {
        let many = (1...13).map { PlanEntry(title: "t\($0)") }
        XCTAssertThrowsError(try write("", date: "2026-07-06", many)) {
            XCTAssertEqual($0 as? PlanWriterError, .tooManyEntries(13))
        }
    }

    func testRejectsTwoNewTasks() {
        // Two titles that match nothing in the file = two new tasks.
        XCTAssertThrowsError(try write(
            "## 2026-07-06\n- [ ] known\n", date: "2026-07-06",
            [PlanEntry(title: "brand new one"), PlanEntry(title: "brand new two")]
        )) {
            XCTAssertEqual($0 as? PlanWriterError, .tooManyNewTasks)
        }
    }

    func testAllowsOneNewTaskAlongsideExistingTitles() throws {
        // "known" exists, "just one new" is the single allowed new task.
        let out = try write(
            "## 2026-07-06\n- [ ] known\n", date: "2026-07-06",
            [PlanEntry(title: "known"), PlanEntry(title: "just one new")]
        )
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] known\n- [ ] just one new\n")
    }

    func testRejectsUnresolvedTaskID() {
        XCTAssertThrowsError(try write(
            "## 2026-07-06\n- [ ] known\n", date: "2026-07-06",
            [PlanEntry(title: "known", taskID: "nope|0|- [ ] ghost")]
        )) {
            XCTAssertEqual($0 as? PlanWriterError, .unresolvedTaskID("nope|0|- [ ] ghost"))
        }
    }

    func testRejectsNonUTF8() {
        let bad = Data([0xFF, 0xFE, 0x00])
        XCTAssertThrowsError(
            try PlanWriter.write(
                date: "2026-07-06", entries: [PlanEntry(title: "x")], in: bad
            )
        ) {
            XCTAssertEqual($0 as? PlanWriterError, .badEncoding)
        }
    }
}
