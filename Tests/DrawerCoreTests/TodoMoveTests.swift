import XCTest
@testable import DrawerCore

final class TodoMoveTests: XCTestCase {
    func testMovePreservesCheckboxDurationAndNote() throws {
        let input = """
        ## 2026-08-28
        - [/] Ship the phone app (45m)
            Keep the markdown source of truth.
            Make the haptics restrained.

        ## Backlog
        - [ ] Existing backlog task
        """.data(using: .utf8)!

        let output = try TodoWriteback.move(
            line: "- [/] Ship the phone app (45m)",
            sectionDate: "2026-08-28",
            toSectionKey: TodoParser.backlogKey,
            displayHeading: "Backlog",
            in: input
        )
        let text = String(decoding: output, as: UTF8.self)

        XCTAssertFalse(text.contains("## 2026-08-28\n- [/] Ship the phone app"))
        XCTAssertTrue(text.contains("## Backlog\n- [ ] Existing backlog task\n- [/] Ship the phone app (45m)\n    Keep the markdown source of truth.\n    Make the haptics restrained."))
    }

    func testMoveCreatesDestinationSection() throws {
        let input = """
        ## 2026-08-28
        - [ ] Move me
        """.data(using: .utf8)!

        let output = try TodoWriteback.move(
            line: "- [ ] Move me",
            sectionDate: "2026-08-28",
            toSectionKey: "2026-08-29",
            displayHeading: "2026-08-29",
            in: input
        )
        let text = String(decoding: output, as: UTF8.self)

        XCTAssertTrue(text.contains("## 2026-08-29\n- [ ] Move me"))
        let display = TodoParser.display(sections: TodoParser.parse(text), today: "2026-08-28")
        XCTAssertEqual(display.upcoming.map(\.title), ["Move me"])
    }

    func testMoveTargetsCorrectDuplicateOccurrence() throws {
        let input = """
        ## 2026-08-27
        - [ ] Same
        - [ ] Same
            second one

        ## 2026-08-28
        - [ ] Today
        """.data(using: .utf8)!

        let output = try TodoWriteback.move(
            line: "- [ ] Same",
            sectionDate: "2026-08-27",
            occurrence: 1,
            toSectionKey: "2026-08-28",
            displayHeading: "2026-08-28",
            in: input
        )
        let text = String(decoding: output, as: UTF8.self)
        let sections = TodoParser.parse(text)
        let old = sections.first(where: { $0.date == "2026-08-27" })?.items ?? []
        let today = sections.first(where: { $0.date == "2026-08-28" })?.items ?? []

        XCTAssertEqual(old.count, 1)
        XCTAssertNil(old[0].note)
        XCTAssertEqual(today.map(\.title), ["Today", "Same"])
        XCTAssertEqual(today.last?.note, "second one")
    }

    func testMoveWithinSameSectionIsNoOp() throws {
        let input = "## Backlog\n- [ ] Keep me\n".data(using: .utf8)!
        let output = try TodoWriteback.move(
            line: "- [ ] Keep me",
            sectionDate: TodoParser.backlogKey,
            toSectionKey: TodoParser.backlogKey,
            displayHeading: "Backlog",
            in: input
        )
        XCTAssertEqual(output, input)
    }
}
