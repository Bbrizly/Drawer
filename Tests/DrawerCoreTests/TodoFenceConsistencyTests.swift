import Foundation
import Testing
@testable import DrawerCore

@Suite("Todo Markdown fence consistency")
struct TodoFenceConsistencyTests {
    @Test("Backtick and tilde fences are both recognized")
    func recognizesBothFenceMarkers() {
        #expect(TodoParser.fenceMarker("```") == "`")
        #expect(TodoParser.fenceMarker("```swift") == "`")
        #expect(TodoParser.fenceMarker("~~~") == "~")
        #expect(TodoParser.fenceMarker("   ~~~yaml") == "~")
        #expect(TodoParser.fenceMarker("text ~~~") == nil)
    }

    @Test("Only the matching marker closes a fenced block")
    func mixedMarkersDoNotCloseFence() {
        let source = """
        ## 2026-08-31
        ~~~text
        - [ ] Hidden in tilde fence
        ```
        - [ ] Still hidden because backticks do not close tildes
        ~~~
        - [ ] Visible task
        """

        let items = TodoParser.parse(source).flatMap(\.items)
        #expect(items.map(\.title) == ["Visible task"])

        let roles = TodoParser.lineRoles(source.components(separatedBy: "\n"))
        #expect(roles[1] == .fence)
        #expect(roles[2] == .fenced)
        #expect(roles[3] == .fenced)
        #expect(roles[4] == .fenced)
        #expect(roles[5] == .fence)
        #expect(roles[6] == .task)
    }

    @Test("Tilde-fenced task-looking content cannot become a recurring task")
    func recurrenceAndParserAgreeOnTildeFences() throws {
        let series = "11111111-1111-1111-1111-111111111111"
        let source = """
        ## 2026-08-31
        ~~~markdown
        - [x] Not a Drawer task
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-31 -->
        ~~~
        - [x] Real recurring task
            <!-- drawer:repeat v=1 series=\(series) rule=daily scheduled=2026-08-31 -->
        """

        let parsed = TodoParser.parse(source)
        let item = try #require(parsed.first?.items.first)
        #expect(item.title == "Real recurring task")

        let reconciled = try TodoRecurrenceWriteback.reconcile(
            in: Data(source.utf8),
            today: "2026-08-31"
        )
        let text = try #require(String(data: reconciled, encoding: .utf8))

        #expect(text.contains("## 2026-09-01"))
        #expect(text.components(separatedBy: "Not a Drawer task").count - 1 == 1)
        #expect(text.components(separatedBy: "Real recurring task").count - 1 == 2)
    }
}
