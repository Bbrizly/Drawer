import XCTest
@testable import DrawerCore

final class TodoWritebackTests: XCTestCase {
    func testTogglesUncheckedToChecked() throws {
        let data = Data("## 2026-06-07\n- [ ] task one\n- [ ] task two\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] task two", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task one\n- [x] task two\n"
        )
    }

    func testToggleFindsTaskAfterIndentedFenceNote() throws {
        // An indented ``` under a task is note text to TodoParser, not a
        // fence; toggle must still reach the tasks below it.
        let data = Data("## 2026-06-07\n- [ ] a\n    ```\n- [ ] b\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] b", sectionDate: "2026-06-07", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] a\n    ```\n- [x] b\n"
        )
    }

    func testSetNoteWorksAfterIndentedFenceNote() throws {
        let data = Data("## 2026-06-07\n- [ ] a\n    ```\n- [ ] b\n".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] b", sectionDate: "2026-06-07", note: "hi", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] a\n    ```\n- [ ] b\n    hi\n"
        )
    }

    func testMarksInProgress() throws {
        let data = Data("## 2026-06-07\n- [ ] task one\n- [ ] task two\n".utf8)
        let out = try TodoWriteback.setInProgress(
            line: "- [ ] task one", sectionDate: "2026-06-07", inProgress: true, in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [/] task one\n- [ ] task two\n"
        )
    }

    func testClearsInProgress() throws {
        let data = Data("## 2026-06-07\n- [/] task one\n".utf8)
        let out = try TodoWriteback.setInProgress(
            line: "- [/] task one", sectionDate: "2026-06-07", inProgress: false, in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task one\n"
        )
    }

    func testTogglingInProgressTaskCompletesIt() throws {
        let data = Data("## 2026-06-07\n- [/] task one\n".utf8)
        let out = try TodoWriteback.toggle(
            line: "- [/] task one", sectionDate: "2026-06-07", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [x] task one\n"
        )
    }

    func testDeletesLineFromSection() throws {
        let data = Data("## 2026-06-07\n- [ ] task one\n- [ ] task two\n".utf8)
        let out = try TodoWriteback.delete(
            line: "- [ ] task one", sectionDate: "2026-06-07", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task two\n"
        )
    }

    func testDeleteScopedToSectionAndOccurrence() throws {
        let data = Data("## 2026-06-07\n- [ ] dup\n- [ ] dup\n## Backlog\n- [ ] dup\n".utf8)
        let out = try TodoWriteback.delete(
            line: "- [ ] dup", sectionDate: "2026-06-07", occurrence: 1, in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] dup\n## Backlog\n- [ ] dup\n"
        )
    }

    func testDeletesLastLineWithoutTrailingNewline() throws {
        let data = Data("## 2026-06-07\n- [ ] only".utf8)
        let out = try TodoWriteback.delete(
            line: "- [ ] only", sectionDate: "2026-06-07", in: data
        )
        XCTAssertEqual(String(data: out, encoding: .utf8), "## 2026-06-07\n")
    }

    func testDeleteLineNotFoundThrows() {
        let data = Data("## 2026-06-07\n- [ ] task\n".utf8)
        XCTAssertThrowsError(
            try TodoWriteback.delete(line: "- [ ] nope", sectionDate: "2026-06-07", in: data)
        )
    }

    func testDeleteRemovesDescriptionWithTask() throws {
        let data = Data("## 2026-06-07\n- [ ] task\n    a note\n    more\n- [ ] keep\n".utf8)
        let out = try TodoWriteback.delete(
            line: "- [ ] task", sectionDate: "2026-06-07", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] keep\n"
        )
    }

    func testSetNoteAddsDescription() throws {
        let data = Data("## 2026-06-07\n- [ ] task\n- [ ] other\n".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] task", sectionDate: "2026-06-07", note: "why this matters", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task\n    why this matters\n- [ ] other\n"
        )
    }

    func testSetNoteReplacesExistingDescription() throws {
        let data = Data("## 2026-06-07\n- [ ] task\n    old note\n- [ ] other\n".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] task", sectionDate: "2026-06-07", note: "new note", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task\n    new note\n- [ ] other\n"
        )
    }

    func testSetNoteMultiLineDescription() throws {
        let data = Data("## 2026-06-07\n- [ ] task\n".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] task", sectionDate: "2026-06-07", note: "line one\nline two", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task\n    line one\n    line two\n"
        )
    }

    func testSetNoteEmptyRemovesDescription() throws {
        let data = Data("## 2026-06-07\n- [ ] task\n    old note\n- [ ] other\n".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] task", sectionDate: "2026-06-07", note: "", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task\n- [ ] other\n"
        )
    }

    func testSetNoteOnLastLineWithoutTrailingNewline() throws {
        let data = Data("## 2026-06-07\n- [ ] task".utf8)
        let out = try TodoWriteback.setNote(
            line: "- [ ] task", sectionDate: "2026-06-07", note: "detail", in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] task\n    detail\n"
        )
    }

    func testTogglesCheckedToUnchecked() throws {
        let data = Data("- [x] done\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [x] done", in: data)
        XCTAssertEqual(String(data: out, encoding: .utf8), "- [ ] done\n")
    }

    func testTogglesUppercaseX() throws {
        let data = Data("- [X] done\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [X] done", in: data)
        XCTAssertEqual(String(data: out, encoding: .utf8), "- [ ] done\n")
    }

    func testPreservesCRLFAndNoTrailingNewline() throws {
        let data = Data("## 2026-06-07\r\n- [ ] crlf task".utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] crlf task", in: data)
        XCTAssertEqual(String(data: out, encoding: .utf8), "## 2026-06-07\r\n- [x] crlf task")
    }

    func testPreservesEverythingElseByteForByte() throws {
        let original = "# Title\n\n## 2026-06-07\n- [ ] a\nplain text\n- [ ] b\n\ntrailing\n"
        let data = Data(original.utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] b", in: data)
        let expected = original.replacingOccurrences(of: "- [ ] b", with: "- [x] b")
        XCTAssertEqual(out, Data(expected.utf8))
    }

    func testLineNotFoundThrows() {
        let data = Data("- [ ] something\n".utf8)
        XCTAssertThrowsError(try TodoWriteback.toggle(line: "- [ ] gone", in: data)) { error in
            XCTAssertEqual(error as? WritebackError, .lineNotFound)
        }
    }

    func testPartialLineMatchRejected() throws {
        // "- [ ] task" must not match inside "- [ ] task extended"
        let data = Data("- [ ] task extended\n- [ ] task\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] task", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "- [ ] task extended\n- [x] task\n"
        )
    }

    func testDuplicateLinesFlipsFirst() throws {
        let data = Data("- [ ] same\n- [ ] same\n".utf8)
        let out = try TodoWriteback.toggle(line: "- [ ] same", in: data)
        XCTAssertEqual(String(data: out, encoding: .utf8), "- [x] same\n- [ ] same\n")
    }

    func testOccurrenceSelectsAmongDuplicates() throws {
        let data = Data("## 2026-06-07\n- [ ] same\n- [ ] same\n- [ ] same\n".utf8)
        let out = try TodoWriteback.toggle(
            line: "- [ ] same", sectionDate: "2026-06-07", occurrence: 1, in: data
        )
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] same\n- [x] same\n- [ ] same\n"
        )
    }

    func testOccurrenceBeyondMatchesThrows() {
        let data = Data("## 2026-06-07\n- [ ] same\n".utf8)
        XCTAssertThrowsError(try TodoWriteback.toggle(
            line: "- [ ] same", sectionDate: "2026-06-07", occurrence: 1, in: data
        )) { error in
            XCTAssertEqual(error as? WritebackError, .lineNotFound)
        }
    }

    func testImpossibleDateHeadingNotASectionForToggle() {
        // Parser ignores tasks under impossible dates; writeback must agree.
        let data = Data("## 2026-13-99\n- [ ] orphan\n".utf8)
        XCTAssertThrowsError(try TodoWriteback.toggle(
            line: "- [ ] orphan", sectionDate: "2026-13-99", in: data
        ))
    }

    func testToggleCanBeScopedToDateSection() throws {
        let data = Data("""
        ## 2026-06-01
        - [ ] same
        ## 2026-06-07
        - [ ] same

        """.utf8)

        let out = try TodoWriteback.toggle(
            line: "- [ ] same",
            sectionDate: "2026-06-07",
            in: data
        )

        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            """
            ## 2026-06-01
            - [ ] same
            ## 2026-06-07
            - [x] same

            """
        )
    }

    func testToggleScopedToBacklogSection() throws {
        // Same line under a day and under Backlog; the backlog one flips.
        let data = Data("""
        ## 2026-06-07
        - [ ] same
        ## Backlog
        - [ ] same

        """.utf8)

        let out = try TodoWriteback.toggle(
            line: "- [ ] same", sectionDate: "backlog", in: data
        )

        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            """
            ## 2026-06-07
            - [ ] same
            ## Backlog
            - [x] same

            """
        )
    }

    func testToggleScopedToArchiveSection() throws {
        // Same line under a day and under Archive; the archive one flips.
        let data = Data("""
        ## 2026-06-07
        - [ ] same
        ## Archive
        - [ ] same

        """.utf8)

        let out = try TodoWriteback.toggle(
            line: "- [ ] same", sectionDate: "archive", in: data
        )

        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            """
            ## 2026-06-07
            - [ ] same
            ## Archive
            - [x] same

            """
        )
    }

    func testAppendToExistingTodaySection() throws {
        let data = Data("## 2026-06-07\n- [ ] first\n\n## 2026-06-09\n- [ ] future\n".utf8)
        let out = try TodoWriteback.append(title: "second", today: "2026-06-07", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] first\n- [ ] second\n\n## 2026-06-09\n- [ ] future\n"
        )
    }

    func testAppendToLastSection() throws {
        let data = Data("## 2026-06-07\n- [ ] first\n".utf8)
        let out = try TodoWriteback.append(title: "second", today: "2026-06-07", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] first\n- [ ] second\n"
        )
    }

    func testAppendCreatesMissingSection() throws {
        let data = Data("---\ntype: drawer\n---\n\n## 2026-06-05\n- [ ] old\n".utf8)
        let out = try TodoWriteback.append(title: "new task", today: "2026-06-07", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "---\ntype: drawer\n---\n\n## 2026-06-05\n- [ ] old\n\n## 2026-06-07\n- [ ] new task\n"
        )
    }

    func testAppendIntoWeekdayPrefixedHeading() throws {
        let data = Data("## Mon 2026-06-08\n- [ ] first\n\n## This week\n- [ ] later\n".utf8)
        let out = try TodoWriteback.append(title: "second", today: "2026-06-08", in: data)
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## Mon 2026-06-08\n- [ ] first\n- [ ] second\n\n## This week\n- [ ] later\n"
        )
    }

    func testAppendToEmptyFile() throws {
        let out = try TodoWriteback.append(title: "first ever", today: "2026-06-07", in: Data())
        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            "## 2026-06-07\n- [ ] first ever\n"
        )
    }

    func testAppendPreservesBOMAndCRLF() throws {
        let bom = [UInt8](arrayLiteral: 0xEF, 0xBB, 0xBF)
        let data = Data(bom + Array("## 2026-06-07\r\n- [ ] first\r\n".utf8))

        let out = try TodoWriteback.append(title: "second", today: "2026-06-07", in: data)

        XCTAssertEqual(
            out,
            Data(bom + Array("## 2026-06-07\r\n- [ ] first\r\n- [ ] second\r\n".utf8))
        )
    }

    func testAppendIgnoresDateHeadingsInsideCodeFences() throws {
        let data = Data("""
        ```
        ## 2026-06-07
        sample
        ```

        """.utf8)

        let out = try TodoWriteback.append(title: "real task", today: "2026-06-07", in: data)

        XCTAssertEqual(
            String(data: out, encoding: .utf8),
            """
            ```
            ## 2026-06-07
            sample
            ```

            ## 2026-06-07
            - [ ] real task

            """
        )
    }
}
