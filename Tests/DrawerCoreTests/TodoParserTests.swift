import XCTest
@testable import DrawerCore

final class TodoParserTests: XCTestCase {
    func testParsesSectionsAndTasks() {
        let text = """
        ## 2026-06-07
        - [ ] Call Housing Services (15m)
        - [x] Texts for the money
        """
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].date, "2026-06-07")
        XCTAssertEqual(sections[0].items.count, 2)
        XCTAssertEqual(sections[0].items[0].title, "Call Housing Services")
        XCTAssertEqual(sections[0].items[0].minutes, 15)
        XCTAssertFalse(sections[0].items[0].isDone)
        XCTAssertTrue(sections[0].items[1].isDone)
        XCTAssertEqual(sections[0].items[1].minutes, 25) // default
    }

    func testParsesInProgressMarker() {
        let text = """
        ## 2026-06-07
        - [/] Working on this now
        - [ ] Not started
        - [x] Finished
        """
        let items = TodoParser.parse(text)[0].items
        XCTAssertTrue(items[0].isInProgress)
        XCTAssertFalse(items[0].isDone)
        XCTAssertEqual(items[0].title, "Working on this now")
        XCTAssertFalse(items[1].isInProgress)
        XCTAssertFalse(items[2].isInProgress)
        XCTAssertTrue(items[2].isDone)
    }

    func testParsesIndentedDescription() {
        let text = """
        ## 2026-06-07
        - [ ] Call the landlord
            Ask about the lease renewal.
            Mention the broken heater too.
        - [ ] Next task
        """
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "Call the landlord")
        XCTAssertEqual(
            items[0].note,
            "Ask about the lease renewal.\nMention the broken heater too."
        )
        XCTAssertNil(items[1].note)
    }

    func testDescriptionStopsAtBlankLine() {
        let text = "## 2026-06-07\n- [ ] Task\n    a detail\n\n    not part of it\n"
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].note, "a detail")
    }

    func testNestedTaskIsNotADescription() {
        let text = "## 2026-06-07\n- [ ] Parent\n    - [ ] Child\n"
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.count, 2)
        XCTAssertNil(items[0].note)
        XCTAssertEqual(items[1].title, "Child")
    }

    func testUppercaseXAndIndent() {
        let text = "## 2026-06-07\n  - [X] done thing"
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isDone)
        XCTAssertEqual(items[0].rawLine, "  - [X] done thing")
    }

    func testIgnoresCodeFences() {
        let text = """
        ## 2026-06-07
        ```
        - [ ] not a task
        ```
        - [ ] real task
        """
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.map(\.title), ["real task"])
    }

    func testTasksOutsideSectionsIgnored() {
        let text = "- [ ] orphan\n## 2026-06-07\n- [ ] real"
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.map(\.title), ["real"])
    }

    func testDurationBoundsAndPlacement() {
        let text = """
        ## 2026-06-07
        - [ ] too big (999m)
        - [ ] mid (30m) sentence continues
        - [ ] good (45m)
        """
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items[0].minutes, 25) // out of bounds -> default, hint kept in title
        XCTAssertEqual(items[0].title, "too big (999m)")
        XCTAssertEqual(items[1].minutes, 25) // not at end of line
        XCTAssertEqual(items[2].minutes, 45)
        XCTAssertEqual(items[2].title, "good")
    }

    func testMalformedHeadingsAreContent() {
        let text = "## not-a-date\n- [ ] ignored\n## 2026-06-07\n- [ ] real"
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.map(\.date), ["2026-06-07"])
        XCTAssertEqual(sections[0].items.map(\.title), ["real"])
    }

    func testDuplicateLinesGetDistinctIDs() {
        let text = "## 2026-06-07\n- [ ] same task\n- [ ] same task"
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertEqual(items[0].occurrence, 0)
        XCTAssertEqual(items[1].occurrence, 1)
    }

    func testImpossibleDateHeadingEndsSection() {
        let text = """
        ## 2026-06-07
        - [ ] real task
        ## 2026-13-99
        - [ ] orphan under impossible date
        """
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.map(\.date), ["2026-06-07"])
        XCTAssertEqual(sections[0].items.map(\.title), ["real task"])
    }

    func testWeekdayPrefixedHeadings() {
        let text = "## Mon 2026-06-08\n- [ ] monday task"
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.map(\.date), ["2026-06-08"])
        XCTAssertEqual(sections[0].items.map(\.title), ["monday task"])
    }

    func testNonDateHeadingEndsDateSection() {
        let text = """
        ## 2026-06-07
        - [ ] day task
        ## This week
        - [ ] backlog task
        """
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections[0].items.map(\.title), ["day task"]) // backlog NOT attached
    }

    func testDisplayTodayAndNearestEarlierCarryover() {
        let text = """
        ## 2026-06-01
        - [ ] old unchecked
        ## 2026-06-05
        - [ ] recent unchecked
        - [x] recent done
        ## 2026-06-07
        - [ ] today task
        ## 2026-06-09
        - [ ] future task
        """
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.today.map(\.title), ["today task"])
        XCTAssertEqual(d.carried.map(\.title), ["recent unchecked"]) // nearest earlier, unchecked only
        XCTAssertEqual(d.upcoming.map(\.title), ["future task"])     // nearest future
        XCTAssertEqual(d.upcomingDate, "2026-06-09")
    }

    func testUpcomingIncludesCheckedItems() {
        // Checked tomorrow-tasks stay visible; hiding them is the
        // view-level "Hide completed" toggle's job.
        let text = """
        ## 2026-06-07
        - [ ] today task
        ## 2026-06-08
        - [x] already done
        - [ ] still open
        """
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.upcoming.map(\.title), ["already done", "still open"])
    }

    func testUpcomingEmptyWhenNoFutureSections() {
        let text = "## 2026-06-07\n- [ ] today task"
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.upcoming, [])
        XCTAssertNil(d.upcomingDate)
    }

    func testDisplayNoTodaySection() {
        let text = "## 2026-06-05\n- [ ] pending"
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.today, [])
        XCTAssertEqual(d.carried.map(\.title), ["pending"])
    }

    func testBacklogSectionParsed() {
        let text = """
        ## 2026-06-07
        - [ ] today task
        ## Backlog
        - [ ] future idea
        - [x] explored idea
        """
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.map(\.date), ["2026-06-07", "backlog"])
        let d = TodoParser.display(sections: sections, today: "2026-06-07")
        XCTAssertEqual(d.backlog.map(\.title), ["future idea", "explored idea"])
        XCTAssertEqual(d.backlog[0].sectionDate, "backlog")
    }

    func testBacklogHeadingCaseInsensitive() {
        let text = "## BackLog\n- [ ] idea"
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.backlog.map(\.title), ["idea"])
    }

    func testBacklogNeverLeaksIntoDayLists() {
        // "backlog" > any ISO date as a string; must not become Tomorrow.
        let text = """
        ## 2026-06-07
        - [ ] today task
        ## Backlog
        - [ ] idea
        """
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.upcoming, [])
        XCTAssertNil(d.upcomingDate)
        XCTAssertEqual(d.carried, [])
    }

    func testArchiveSectionParsed() {
        let text = """
        ## 2026-06-07
        - [ ] today task
        ## Archive
        Swept from the vault. Parked, not active.
        ### Games
        - [ ] parked game idea
        - [x] explored idea
        """
        let sections = TodoParser.parse(text)
        XCTAssertEqual(sections.map(\.date), ["2026-06-07", "archive"])
        let d = TodoParser.display(sections: sections, today: "2026-06-07")
        // Prose inside Archive is ignored; "### " subheadings tag the
        // tasks below them so the view can group.
        XCTAssertEqual(d.archive.map(\.title), ["parked game idea", "explored idea"])
        XCTAssertEqual(d.archive[0].sectionDate, "archive")
        XCTAssertEqual(d.archive.map(\.subsection), ["Games", "Games"])
    }

    func testSubsectionTagsTasksAndResetsAtNextSection() {
        let text = """
        ## Archive
        - [ ] before any subheading
        ### Games
        - [ ] game idea
        ### AI / apps
        - [ ] app idea
        ## 2026-06-07
        - [ ] day task
        """
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(
            d.archive.map(\.subsection), [nil, "Games", "AI / apps"]
        )
        // "### " never leaks across a "## " boundary.
        XCTAssertEqual(d.today.map(\.subsection), [nil])
    }

    func testArchiveHeadingCaseInsensitive() {
        let text = "## ARCHIVE\n- [ ] idea"
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.archive.map(\.title), ["idea"])
    }

    func testArchiveNeverLeaksIntoDayLists() {
        // "archive" < any ISO date as a string; must not fake a carryover.
        let text = """
        ## 2026-06-07
        - [ ] today task
        ## Archive
        - [ ] idea
        """
        let d = TodoParser.display(sections: TodoParser.parse(text), today: "2026-06-07")
        XCTAssertEqual(d.upcoming, [])
        XCTAssertNil(d.upcomingDate)
        XCTAssertEqual(d.carried, [])
        XCTAssertEqual(d.backlog, [])
    }

    func testCRLFLines() {
        let text = "## 2026-06-07\r\n- [ ] crlf task\r\n"
        let items = TodoParser.parse(text)[0].items
        XCTAssertEqual(items[0].rawLine, "- [ ] crlf task") // no trailing \r
    }
}
