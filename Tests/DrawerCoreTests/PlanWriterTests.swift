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

    // MARK: injection / hardening (codex review findings)

    func testRejectsNewlineInTitle() {
        XCTAssertThrowsError(try write(
            "", date: "2026-07-06", [PlanEntry(title: "one\n- [ ] sneaky two")]
        )) {
            XCTAssertEqual($0 as? PlanWriterError, .invalidEntry("one\n- [ ] sneaky two"))
        }
    }

    func testRejectsSectionInjectionInTitle() {
        XCTAssertThrowsError(try write(
            "", date: "2026-07-06", [PlanEntry(title: "one\n## 2026-07-07\n- [ ] two")]
        )) {
            guard case .invalidEntry = ($0 as? PlanWriterError) else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
    }

    func testRejectsUnicodeLineSeparatorInTitle() {
        // TodoParser splits on Character.isNewline, so U+2028 re-parses as a new
        // column-0 line. The guard must reject it, not just \n and \r.
        let title = "one\u{2028}## 2026-12-31\u{2028}- [ ] injected"
        XCTAssertThrowsError(try write("", date: "2026-07-06", [PlanEntry(title: title)])) {
            guard case .invalidEntry = ($0 as? PlanWriterError) else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
    }

    func testRejectsCRLFGraphemeInTitle() {
        // "\r\n" is a single Swift Character, so contains("\n")/contains("\r")
        // both miss it; contains(where: \.isNewline) catches it.
        let title = "one\r\n## 2026-12-31\r\n- [ ] injected"
        XCTAssertThrowsError(try write("", date: "2026-07-06", [PlanEntry(title: title)])) {
            guard case .invalidEntry = ($0 as? PlanWriterError) else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
    }

    func testUnicodeSeparatorInNoteStaysIndentedNotInjected() throws {
        // A note carrying a U+2028 heading must render as indented note lines, so
        // it can never de-indent into a real column-0 section on re-parse.
        let out = try write(
            "", date: "2026-07-06",
            [PlanEntry(title: "real task", note: "harmless\u{2028}## 2026-12-31")]
        )
        XCTAssertFalse(out.contains("\n## 2026-12-31"), "note injected a real section")
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] real task\n    harmless\n    ## 2026-12-31\n")
    }

    func testRejectsCheckboxShapedNoteLine() {
        XCTAssertThrowsError(try write(
            "", date: "2026-07-06",
            [PlanEntry(title: "real task", note: "- [ ] injected task")]
        )) {
            guard case .invalidEntry = ($0 as? PlanWriterError) else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
    }

    func testRejectsEmptyTitle() {
        XCTAssertThrowsError(try write("", date: "2026-07-06", [PlanEntry(title: "   ")])) {
            guard case .invalidEntry = ($0 as? PlanWriterError) else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
    }

    func testTaskIDCannotAuthorizeAnUnrelatedTitle() {
        // Real id, but title matches nothing: this is a smuggled new task.
        let file = "## Backlog\n- [ ] ship it\n"
        XCTAssertThrowsError(try write(
            file, date: "2026-07-06",
            [PlanEntry(title: "totally different thing", taskID: "backlog|0|- [ ] ship it")]
        )) {
            XCTAssertEqual(
                $0 as? PlanWriterError, .taskIDTitleMismatch("backlog|0|- [ ] ship it")
            )
        }
    }

    func testReplaceIgnoresFencedCheckboxes() throws {
        // A fenced code sample under the target date must survive replace:true;
        // TodoParser never treats it as a task, so neither may the writer.
        let file = "## 2026-07-06\n- [ ] real todo\n```\n- [ ] fenced sample\n```\n"
        let out = try write(file, date: "2026-07-06", [PlanEntry(title: "planned")], replace: true)
        XCTAssertEqual(
            out, "## 2026-07-06\n```\n- [ ] fenced sample\n```\n- [ ] planned\n"
        )
    }

    // MARK: fence and content safety

    func testIndentedFenceNoteDoesNotWidenReplaceToLaterDays() throws {
        // An indented ``` line under a task is note text to TodoParser, so the
        // writer must not treat it as a fence: a replace of day A may never
        // reach day B's tasks.
        let file = "## 2026-07-06\n- [ ] a\n    ```\n\n## 2026-07-07\n- [ ] b\n"
        let out = try write(file, date: "2026-07-06", [PlanEntry(title: "planned")], replace: true)
        XCTAssertTrue(out.contains("- [ ] b"), "later day's task must survive: \(out)")
        let planned = out.range(of: "- [ ] planned")
        let laterDay = out.range(of: "## 2026-07-07")
        XCTAssertNotNil(planned)
        XCTAssertNotNil(laterDay)
        XCTAssertTrue(planned!.lowerBound < laterDay!.lowerBound,
                      "new entry must land under the edited day: \(out)")
    }

    func testRejectsFenceLineInNote() {
        XCTAssertThrowsError(try write(
            "", date: "2026-07-06",
            [PlanEntry(title: "x", note: "```swift\nlet x = 1")]
        )) {
            XCTAssertEqual($0 as? PlanWriterError, .invalidEntry("x"))
        }
    }

    func testRejectsOutOfRangeMinutes() {
        for m in [0, -5, 481] {
            XCTAssertThrowsError(
                try write("", date: "2026-07-06", [PlanEntry(title: "x", minutes: m)]),
                "minutes \(m) must be rejected"
            ) {
                XCTAssertEqual($0 as? PlanWriterError, .invalidEntry("x"))
            }
        }
    }

    func testRejectsOversizedTitleAndNote() {
        // One MCP call must not be able to balloon the shared, synced file.
        let bigTitle = String(repeating: "a", count: 501)
        XCTAssertThrowsError(try write("", date: "2026-07-06", [PlanEntry(title: bigTitle)]))
        let bigNote = String(repeating: "b", count: 4097)
        XCTAssertThrowsError(try write("", date: "2026-07-06", [PlanEntry(title: "x", note: bigNote)]))
        // At the limit is fine.
        XCTAssertNoThrow(try write(
            "", date: "2026-07-06",
            [PlanEntry(title: String(repeating: "a", count: 500),
                       note: String(repeating: "b", count: 4096))]))
    }

    func testBlankInteriorNoteLineIsSkipped() throws {
        // A whitespace-only note line would end the note on re-parse and
        // orphan the rest, so render drops it.
        let out = try write("", date: "2026-07-06", [PlanEntry(title: "x", note: "a\n\nb")])
        XCTAssertEqual(out, "## 2026-07-06\n- [ ] x\n    a\n    b\n")
    }

    func testReplaceKeepsBareCheckboxPlaceholder() throws {
        // "- [ ]" with no trailing space is not a task to TodoParser, so
        // replace must leave it alone while dropping the real unchecked task.
        let file = "## 2026-07-06\n- [ ]\n- [ ] real\n"
        let out = try write(file, date: "2026-07-06", [PlanEntry(title: "planned")], replace: true)
        XCTAssertTrue(out.contains("- [ ]\n"), "placeholder must survive: \(out)")
        XCTAssertFalse(out.contains("- [ ] real"))
    }

    func testRejectsInvalidDate() {
        XCTAssertThrowsError(try write("", date: "tomorrow", [PlanEntry(title: "x")])) {
            XCTAssertEqual($0 as? PlanWriterError, .invalidDate("tomorrow"))
        }
        XCTAssertThrowsError(try write("", date: "2026-99-99", [PlanEntry(title: "x")])) {
            XCTAssertEqual($0 as? PlanWriterError, .invalidDate("2026-99-99"))
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
