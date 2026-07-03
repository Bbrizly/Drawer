import XCTest
@testable import DrawerCore

final class WorkLogMarkdownTests: XCTestCase {
    func testEmptyLogRendersPlaceholder() {
        let markdown = renderWorkLogMarkdown([])
        XCTAssertTrue(markdown.contains("No work logged yet"))
    }

    func testRendersDayHeadingAndRows() {
        let summary = WorkSummary(
            day: "2026-07-01",
            rows: [
                WorkSummary.Row(taskTitle: "B", seconds: 3600),
                WorkSummary.Row(taskTitle: "A", seconds: 600),
            ],
            total: 4200,
            longest: nil
        )
        let markdown = renderWorkLogMarkdown([summary])
        XCTAssertTrue(markdown.contains("## 2026-07-01 — 1h 10m"))
        XCTAssertTrue(markdown.contains("- B — 1h 00m"))
        XCTAssertTrue(markdown.contains("- A — 0h 10m"))
    }
}
