import Foundation

/// Metadata-aware child-block edits shared by mobile and future recurrence UI.
/// Drawer-owned HTML comments stay attached to the task and never leak into
/// the human note text or get erased by editing that text.
public enum TodoMetadataWriteback {
    public static func setNote(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        note: String,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }
        let lines = try markdownLines(in: data)
        let roles = TodoParser.lineRoles(lines.map(\.text))
        let newline = preferredNewline(in: lines, data: data)
        var currentSection: String?
        var seen = 0

        for index in lines.indices {
            let line = lines[index]
            if roles[index] == .fence || roles[index] == .fenced { continue }
            if roles[index] == .heading {
                currentSection = TodoParser.sectionKey(fromHeading: line.text)
                continue
            }
            guard currentSection == sectionDate, line.text == rawLine else { continue }
            if seen < occurrence { seen += 1; continue }

            var end = line.fullRange.upperBound
            var metadata: [Data] = []
            var child = index + 1
            while child < lines.endIndex, roles[child] == .note {
                end = lines[child].fullRange.upperBound
                if TodoParser.isDrawerMetadataLine(lines[child].text) {
                    metadata.append(data.subdata(in: lines[child].contentRange))
                }
                child += 1
            }

            let indent = String(rawLine.prefix { $0 == " " || $0 == "\t" }) + "    "
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            var insertion = Data()
            let hasChildren = !trimmed.isEmpty || !metadata.isEmpty
            if hasChildren, line.contentRange.upperBound == line.fullRange.upperBound {
                insertion.append(newline)
            }
            if !trimmed.isEmpty {
                for noteLine in trimmed.components(separatedBy: "\n") {
                    insertion.append(Data((indent + noteLine.trimmingCharacters(in: .whitespaces)).utf8))
                    insertion.append(newline)
                }
            }
            for metadataLine in metadata {
                insertion.append(metadataLine)
                insertion.append(newline)
            }

            var out = data
            out.replaceSubrange(line.fullRange.upperBound..<end, with: insertion)
            return out
        }
        throw WritebackError.lineNotFound
    }

    private struct MarkdownLine {
        let contentRange: Range<Data.Index>
        let fullRange: Range<Data.Index>
        let text: String
    }

    private static func markdownLines(in data: Data) throws -> [MarkdownLine] {
        guard String(data: data, encoding: .utf8) != nil else { throw WritebackError.badEncoding }
        var result: [MarkdownLine] = []
        var start = data.startIndex
        var index = start
        while index < data.endIndex {
            if data[index] != 0x0A && data[index] != 0x0D {
                index = data.index(after: index)
                continue
            }
            let contentEnd = index
            var end = data.index(after: index)
            if data[index] == 0x0D, end < data.endIndex, data[end] == 0x0A {
                end = data.index(after: end)
            }
            let range = start..<contentEnd
            guard let text = String(data: data.subdata(in: range), encoding: .utf8) else {
                throw WritebackError.badEncoding
            }
            result.append(MarkdownLine(contentRange: range, fullRange: start..<end, text: text))
            start = end
            index = end
        }
        if start < data.endIndex {
            let range = start..<data.endIndex
            guard let text = String(data: data.subdata(in: range), encoding: .utf8) else {
                throw WritebackError.badEncoding
            }
            result.append(MarkdownLine(contentRange: range, fullRange: range, text: text))
        }
        return result
    }

    private static func preferredNewline(in lines: [MarkdownLine], data: Data) -> Data {
        for line in lines where line.fullRange.upperBound > line.contentRange.upperBound {
            return data.subdata(in: line.contentRange.upperBound..<line.fullRange.upperBound)
        }
        return Data("\n".utf8)
    }
}
