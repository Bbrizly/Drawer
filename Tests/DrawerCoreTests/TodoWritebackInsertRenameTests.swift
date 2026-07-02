import XCTest
@testable import DrawerCore

final class TodoWritebackInsertRenameTests: XCTestCase {
    private func d(_ s: String) -> Data { Data(s.utf8) }
    private func s(_ d: Data) -> String { String(data: d, encoding: .utf8)! }

    func testInsertTaskIntoExistingSection() throws {
        let file = "## Backlog\n- [ ] old\n\n## Archive\n- [x] done\n"
        let out = try TodoWriteback.insert(
            line: "- [ ] new", intoSectionKey: "backlog", displayHeading: "Backlog", in: d(file)
        )
        let text = s(out)
        XCTAssertTrue(text.contains("- [ ] old\n- [ ] new"))
        XCTAssertTrue(text.contains("## Archive"))   // untouched
    }

    func testInsertHeaderIntoSection() throws {
        let file = "## Backlog\n- [ ] a\n"
        let out = try TodoWriteback.insert(
            line: "### Ideas", intoSectionKey: "backlog", displayHeading: "Backlog", in: d(file)
        )
        XCTAssertTrue(s(out).contains("### Ideas"))
    }

    func testInsertCreatesMissingSection() throws {
        let file = "## 2026-06-29\n- [ ] today\n"
        let out = try TodoWriteback.insert(
            line: "- [ ] b", intoSectionKey: "backlog", displayHeading: "Backlog", in: d(file)
        )
        let text = s(out)
        XCTAssertTrue(text.contains("## Backlog"))
        XCTAssertTrue(text.contains("- [ ] b"))
    }

    func testRenameReplacesTitleKeepsState() throws {
        let file = "## Backlog\n- [x] old title\n"
        let out = try TodoWriteback.rename(
            line: "- [x] old title", sectionDate: "backlog", to: "new title", in: d(file)
        )
        XCTAssertEqual(s(out), "## Backlog\n- [x] new title\n")
    }

    func testRenamePreservesIndentation() throws {
        let file = "## Backlog\n    - [ ] sub\n"
        let out = try TodoWriteback.rename(
            line: "    - [ ] sub", sectionDate: "backlog", to: "renamed", in: d(file)
        )
        XCTAssertEqual(s(out), "## Backlog\n    - [ ] renamed\n")
    }

    func testRenameMissingThrows() {
        let file = "## Backlog\n- [ ] a\n"
        XCTAssertThrowsError(try TodoWriteback.rename(
            line: "- [ ] missing", sectionDate: "backlog", to: "x", in: d(file)
        ))
    }
}
