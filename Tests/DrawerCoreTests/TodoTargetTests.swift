import XCTest
@testable import DrawerCore

/// A trusted position only works if the parser and the writeback count task
/// lines the same way. Anything that reads like a checkbox but is not a task
/// (a note, a fenced block, prose) has to be invisible to both.
final class TodoTargetTests: XCTestCase {
    /// Every parsed item, addressed by position alone, must flip its own line
    /// and nothing else.
    func testEveryParsedPositionAddressesItsOwnLine() throws {
        let text = """
        preamble - [ ] not in a section

        ## 2026-06-07
        - [ ] one
            remember to - [ ] buy milk
        - [/] two
        ### grouped
        - [x] three
        - [ ] three

        ```
        - [ ] fenced
        ```

        ## Backlog
        - [ ] later
        - [ ] later

        ## 2026-06-07
        - [ ] one more

        ## Archive
        ### Done
        - [x] gone
        """
        let data = Data(text.utf8)
        let lines = text.components(separatedBy: "\n")

        for section in TodoParser.parse(text) {
            for item in section.items {
                let target = TodoTarget(
                    sectionKey: item.sectionDate,
                    rawLine: "no line reads like this",
                    ordinal: item.ordinal,
                    trustsOrdinal: true
                )
                let out = try TodoWriteback.toggle(target: target, in: data)
                let changed = zip(lines, String(decoding: out, as: UTF8.self)
                    .components(separatedBy: "\n"))
                    .enumerated()
                    .filter { $0.element.0 != $0.element.1 }
                XCTAssertEqual(changed.count, 1, "\(item.sectionDate)#\(item.ordinal) hit \(changed.count) lines")
                XCTAssertEqual(
                    changed.first?.element.0, item.rawLine,
                    "\(item.sectionDate)#\(item.ordinal) landed on the wrong line")
            }
        }
    }

    /// Without that trust the old rules still apply: exact text, nth identical
    /// line, and nothing found means nothing changed.
    func testAnUntrustedPositionStillNeedsTheExactLine() {
        let data = Data("## 2026-06-07\n- [ ] a\n- [ ] b\n".utf8)
        let target = TodoTarget(
            sectionKey: "2026-06-07", rawLine: "- [ ] gone", ordinal: 1)

        XCTAssertThrowsError(try TodoWriteback.toggle(target: target, in: data)) {
            XCTAssertEqual($0 as? WritebackError, .lineNotFound)
        }
    }

    /// A position past the end of the section falls back to the text rather
    /// than clamping onto the last row.
    func testAnOutOfRangePositionFallsBackToTheText() throws {
        let data = Data("## 2026-06-07\n- [ ] a\n- [ ] b\n".utf8)
        let target = TodoTarget(
            sectionKey: "2026-06-07", rawLine: "- [ ] a", ordinal: 9, trustsOrdinal: true)

        let out = try TodoWriteback.toggle(target: target, in: data)

        XCTAssertEqual(String(decoding: out, as: UTF8.self), "## 2026-06-07\n- [x] a\n- [ ] b\n")
    }
}
