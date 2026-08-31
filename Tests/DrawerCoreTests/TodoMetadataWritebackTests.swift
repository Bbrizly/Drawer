import Foundation
import Testing
@testable import DrawerCore

@Suite("Todo metadata writeback")
struct TodoMetadataWritebackTests {
    @Test("Drawer recurrence metadata is hidden from human notes")
    func parserHidesMetadata() throws {
        let source = """
        ## 2026-08-31
        - [ ] Read (20m)
            Human note.
            <!-- drawer:repeat v=1 series=11111111-1111-1111-1111-111111111111 rule=daily scheduled=2026-08-31 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        #expect(item.note == "Human note.")
    }

    @Test("Editing a note preserves Drawer metadata byte content")
    func editPreservesMetadata() throws {
        let metadata = "    <!-- drawer:repeat v=1 series=11111111-1111-1111-1111-111111111111 rule=daily scheduled=2026-08-31 -->"
        let source = "## 2026-08-31\r\n- [ ] Read\r\n    Old note.\r\n\(metadata)\r\n"
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoMetadataWriteback.setNote(
            line: item.rawLine,
            sectionDate: item.sectionDate,
            occurrence: item.occurrence,
            note: "New note.",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains("    New note.\r\n"))
        #expect(text.contains(metadata + "\r\n"))
        #expect(!text.contains("Old note."))
        #expect(TodoParser.parse(text).first?.items.first?.note == "New note.")
    }

    @Test("Clearing human note does not clear Drawer metadata")
    func clearPreservesMetadata() throws {
        let source = """
        ## 2026-08-31
        - [ ] Read
            Old note.
            <!-- drawer:repeat v=1 series=11111111-1111-1111-1111-111111111111 rule=daily scheduled=2026-08-31 -->
        """
        let item = try #require(TodoParser.parse(source).first?.items.first)
        let output = try TodoMetadataWriteback.setNote(
            line: item.rawLine,
            sectionDate: item.sectionDate,
            occurrence: item.occurrence,
            note: "",
            in: Data(source.utf8)
        )
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(!text.contains("Old note."))
        #expect(text.contains("drawer:repeat"))
        #expect(TodoParser.parse(text).first?.items.first?.note == nil)
    }
}
