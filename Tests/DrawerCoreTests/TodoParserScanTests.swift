import XCTest
@testable import DrawerCore

/// The task shape, the fence check, and the "(25m)" suffix used to be regexes.
/// They are hand-rolled now, so the shapes that used to fall out of the pattern
/// for free are pinned here instead.
final class TodoParserScanTests: XCTestCase {
    // MARK: taskParts

    func testAcceptsEveryMarker() {
        for marker in [" ", "x", "X", "/"] {
            let parts = TodoParser.taskParts("- [\(marker)] Buy milk")
            XCTAssertEqual(parts?.marker, Character(marker), "marker \(marker)")
            XCTAssertEqual(parts.map { String($0.title) }, "Buy milk")
        }
    }

    func testAllowsLeadingSpacesAndTabs() {
        XCTAssertEqual(TodoParser.taskParts("   - [ ] Indented").map { String($0.title) }, "Indented")
        XCTAssertEqual(TodoParser.taskParts("\t- [x] Tabbed").map { String($0.title) }, "Tabbed")
    }

    func testRejectsNearMisses() {
        let bad = [
            "",
            "   ",
            "- [] No marker",
            "- [z] Wrong marker",
            "- [ ]No space after the box",
            "-[ ] No space after the dash",
            "* [ ] Wrong bullet",
            "## 2026-06-07",
            "Plain text",
            "- [ ",
            "- [x",
            "- [x]",
        ]
        for line in bad {
            XCTAssertNil(TodoParser.taskParts(line), "should reject \(line.debugDescription)")
        }
    }

    func testEmptyTitleIsStillATask() {
        XCTAssertEqual(TodoParser.taskParts("- [ ] ").map { String($0.title) }, "")
    }

    // MARK: fences

    func testFenceLine() {
        XCTAssertTrue(TodoParser.isFenceLine("```"))
        XCTAssertTrue(TodoParser.isFenceLine("```swift"))
        XCTAssertTrue(TodoParser.isFenceLine("    ```"))
        XCTAssertFalse(TodoParser.isFenceLine("``"))
        XCTAssertFalse(TodoParser.isFenceLine("text ```"))
        XCTAssertFalse(TodoParser.isFenceLine(""))
    }

    // MARK: duration

    func testDurationSuffix() {
        let title: Substring = "Call the landlord (15m)"
        let d = TodoParser.duration(in: title)
        XCTAssertEqual(d?.minutes, 15)
        XCTAssertEqual(d.map { String(title[..<$0.titleEnd]).trimmingCharacters(in: .whitespaces) },
                       "Call the landlord")
    }

    func testDurationToleratesTrailingWhitespace() {
        XCTAssertEqual(TodoParser.duration(in: "Task (5m)   ")?.minutes, 5)
        XCTAssertEqual(TodoParser.duration(in: "Task (5m)\t")?.minutes, 5)
    }

    func testDurationRejectsNonSuffixAndMalformed() {
        for title: Substring in [
            "Task (15m) trailing words",
            "Task (m)",
            "Task 15m)",
            "Task (15m",
            "Task",
            "",
            "(15m",
            ")",
        ] {
            XCTAssertNil(TodoParser.duration(in: title), "should reject \(title.debugDescription)")
        }
    }

    func testParenthesesInTitleSurvive() {
        let sections = TodoParser.parse("## 2026-06-07\n- [ ] Email (the good one) (30m)\n")
        XCTAssertEqual(sections.first?.items.first?.title, "Email (the good one)")
        XCTAssertEqual(sections.first?.items.first?.minutes, 30)
    }

    func testOutOfRangeDurationKeepsTheDefaultAndTheText() {
        // 1...480 is the accepted window; anything else stays part of the title.
        let sections = TodoParser.parse("## 2026-06-07\n- [ ] Marathon (999m)\n")
        XCTAssertEqual(sections.first?.items.first?.minutes, 25)
        XCTAssertEqual(sections.first?.items.first?.title, "Marathon (999m)")
    }

    // MARK: description lines

    func testDescriptionLines() {
        XCTAssertTrue(TodoParser.isDescriptionLine("    a note"))
        XCTAssertTrue(TodoParser.isDescriptionLine("\ta note"))
        XCTAssertFalse(TodoParser.isDescriptionLine("a note"), "must be indented")
        XCTAssertFalse(TodoParser.isDescriptionLine("     "), "blank")
        XCTAssertFalse(TodoParser.isDescriptionLine(""), "empty")
        XCTAssertFalse(TodoParser.isDescriptionLine("    - [ ] a nested task"))
    }
}
