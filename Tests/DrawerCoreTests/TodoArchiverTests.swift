import XCTest
@testable import DrawerCore

final class TodoArchiverTests: XCTestCase {
    func testMovesOldDoneIntoExistingArchiveDone() {
        let text = """
        ## 2026-06-07
        - [ ] still open
        - [x] old finished

        ## Archive

        ### Done
        - [x] already archived
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, """
        ## 2026-06-07
        - [ ] still open

        ## Archive

        ### Done
        - [x] already archived
        - [x] old finished
        """)
    }

    func testKeepsRecentDoneInPlace() {
        // 2026-06-12 is exactly 3 days before today, so it stays.
        let text = """
        ## 2026-06-12
        - [x] just finished
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, text)
    }

    func testMovesNoteLinesWithTheTask() {
        let text = """
        ## 2026-06-01
        - [x] shipped thing
            a detail line
            another detail
        - [ ] open thing
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, """
        ## 2026-06-01
        - [ ] open thing

        ## Archive

        ### Done
        - [x] shipped thing
            a detail line
            another detail
        """)
    }

    func testCreatesArchiveAndDoneWhenMissing() {
        let text = """
        ## 2026-06-01
        - [x] old done
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, """
        ## 2026-06-01

        ## Archive

        ### Done
        - [x] old done
        """)
    }

    func testCreatesDoneSubgroupInsideExistingArchive() {
        let text = """
        ## 2026-06-01
        - [x] old done

        ## Archive
        ### Ideas
        - [ ] someday thing
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, """
        ## 2026-06-01

        ## Archive
        ### Done
        - [x] old done
        ### Ideas
        - [ ] someday thing
        """)
    }

    func testIdempotent() {
        let text = """
        ## 2026-06-01
        - [x] old done
        - [ ] open
        """
        let once = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        let twice = TodoArchiver.archiveCompleted(in: once, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(once, twice)
    }

    func testLeavesBacklogAndUndatedDoneAlone() {
        // Done items not under a dated heading are never swept.
        let text = """
        ## Backlog
        - [x] done in backlog

        ## This week
        - [x] done under unknown heading
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, text)
    }

    func testLeavesOpenAndInProgressTasksAlone() {
        let text = """
        ## 2026-06-01
        - [ ] open old task
        - [/] in progress old task
        """
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertEqual(out, text)
    }

    func testPreservesTrailingNewline() {
        let text = "## 2026-06-01\n- [x] old done\n"
        let out = TodoArchiver.archiveCompleted(in: text, today: "2026-06-15", keepDays: 3)
        XCTAssertTrue(out.hasSuffix("\n"))
        XCTAssertTrue(out.contains("### Done"))
    }

    func testInvalidTodayReturnsUnchanged() {
        let text = "## 2026-06-01\n- [x] old done\n"
        XCTAssertEqual(
            TodoArchiver.archiveCompleted(in: text, today: "not-a-date", keepDays: 3),
            text
        )
    }
}
