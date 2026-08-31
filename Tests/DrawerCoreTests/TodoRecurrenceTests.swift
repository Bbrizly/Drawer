import Foundation
import Testing
@testable import DrawerCore

@Suite("Todo recurrence")
struct TodoRecurrenceTests {
    private let series = "11111111-1111-1111-1111-111111111111"

    @Test("Completing a recurring task advances it atomically and preserves group, duration and note")
    func completeAndAdvance() throws {
        let source = """
        ## 2026-08-30

        ### Morning

        - [ ] Read fiction (20m)
            No phone first.
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-30 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoRecurrenceWriteback.completeAndAdvance(
            item: item,
            today: "2026-08-30",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text.contains("- [x] Read fiction (20m)"))
        #expect(text.contains("## 2026-08-31"))
        #expect(text.contains("### Morning"))
        #expect(text.contains("- [ ] Read fiction (20m)"))
        #expect(text.contains("No phone first."))
        #expect(text.contains("series=\(series) rule=daily scheduled=2026-08-31"))
    }

    @Test("Late daily completion advances to the next future day instead of backfilling")
    func lateCompletionSkipsBackfill() throws {
        let source = """
        ## 2026-08-28
        - [ ] Read
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-28 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoRecurrenceWriteback.completeAndAdvance(
            item: item,
            today: "2026-08-31",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains("## 2026-09-01"))
        #expect(!text.contains("## 2026-08-29"))
    }

    @Test("Reconciliation is idempotent after an external completion")
    func reconcileIsIdempotent() throws {
        let source = """
        ## 2026-08-30
        - [x] Read
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-30 -->
        """
        let once = try TodoRecurrenceWriteback.reconcile(in: Data(source.utf8), today: "2026-08-30")
        let twice = try TodoRecurrenceWriteback.reconcile(in: once, today: "2026-08-30")
        #expect(once == twice)
        let text = try #require(String(data: once, encoding: .utf8))
        #expect(text.components(separatedBy: "series=\(series)").count - 1 == 2)
        #expect(text.contains("scheduled=2026-08-31"))
    }

    @Test("A second unresolved copy blocks recurrence advancement")
    func duplicateActiveSeriesIsRejected() throws {
        let source = """
        ## 2026-08-30
        - [ ] Read
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-30 -->

        ## 2026-08-31
        - [ ] Read
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-31 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        #expect(throws: TodoRecurrenceError.duplicateActiveSeries) {
            _ = try TodoRecurrenceWriteback.completeAndAdvance(
                item: item,
                today: "2026-08-30",
                in: Data(source.utf8)
            )
        }
    }

    @Test("Weekday recurrence skips a weekend")
    func weekdaysSkipWeekend() throws {
        let source = """
        ## 2026-08-28
        - [ ] Review
            <!-- drawer:repeat v=1 series=\(series) rule=weekdays:1,2,3,4,5 scheduled=2026-08-28 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoRecurrenceWriteback.completeAndAdvance(
            item: item,
            today: "2026-08-28",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains("## 2026-08-31"))
    }

    @Test("After-completion recurrence anchors to the actual resolution day")
    func afterCompletionUsesResolutionDay() throws {
        let source = """
        ## 2026-08-20
        - [ ] Water plants
            <!-- drawer:repeat v=1 series=\(series) rule=after:7 scheduled=2026-08-20 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoRecurrenceWriteback.completeAndAdvance(
            item: item,
            today: "2026-08-23",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains("## 2026-08-30"))
    }

    @Test("Setting and clearing repeat metadata preserves task content")
    func setAndClear() throws {
        let source = """
        ## 2026-08-30
        - [ ] Stretch (10m)
            Slow and easy.
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let repeated = try TodoRecurrenceWriteback.setRecurrence(
            for: item,
            rule: .daily,
            today: "2026-08-30",
            in: Data(source.utf8)
        )
        let repeatedText = try #require(String(data: repeated, encoding: .utf8))
        #expect(repeatedText.contains("<!-- drawer:repeat v=1"))
        #expect(repeatedText.contains("Slow and easy."))

        let repeatedItem = try #require(TodoParser.parse(repeatedText).first?.items.first)
        let cleared = try TodoRecurrenceWriteback.setRecurrence(
            for: repeatedItem,
            rule: nil,
            today: "2026-08-30",
            in: repeated
        )
        let clearedText = try #require(String(data: cleared, encoding: .utf8))
        #expect(!clearedText.contains("drawer:repeat"))
        #expect(clearedText.contains("Slow and easy."))
    }
}
