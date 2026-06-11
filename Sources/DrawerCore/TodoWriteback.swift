import Foundation

public enum WritebackError: Error, Equatable {
    case lineNotFound
    case badEncoding
}

public enum TodoWriteback {
    /// Flips the checkbox on the exact line `rawLine` inside `data`,
    /// touching only that single byte. Throws if the line is not found
    /// as a complete line (bounded by newlines or file edges).
    public static func toggle(line rawLine: String, in data: Data) throws -> Data {
        try toggle(line: rawLine, sectionDate: nil, in: data)
    }

    /// Flips the exact line only inside sections whose date matches
    /// `sectionDate`. `occurrence` selects among identical lines in that
    /// section (0 = first), matching TodoParser's occurrence numbering.
    public static func toggle(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        in data: Data
    ) throws -> Data {
        try toggle(line: rawLine, sectionDate: Optional(sectionDate), occurrence: occurrence, in: data)
    }

    private static func toggle(
        line rawLine: String,
        sectionDate: String?,
        occurrence: Int = 0,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }

        var currentDate: String?
        var inFence = false
        var seen = 0
        for line in try markdownLines(in: data) {
            if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if line.text.hasPrefix("## ") {
                // Shared with the parser so section boundaries always agree
                // (dates and the "backlog" key alike).
                currentDate = TodoParser.sectionKey(fromHeading: line.text)
                continue
            }
            guard sectionDate == nil || currentDate == sectionDate,
                  line.text == rawLine,
                  let boxIndex = checkboxIndex(in: data, lineRange: line.contentRange)
            else {
                continue
            }
            if seen < occurrence {
                seen += 1
                continue
            }

            var out = data
            let current = out[boxIndex]
            // Checking a blank or in-progress "/" task completes it. Only an
            // already-done task toggles back to blank.
            let done = current == UInt8(ascii: "x") || current == UInt8(ascii: "X")
            out[boxIndex] = done ? UInt8(ascii: " ") : UInt8(ascii: "x")
            return out
        }
        throw WritebackError.lineNotFound
    }

    /// Sets the checkbox on the exact line to "/" (in progress) when
    /// `inProgress` is true, or back to " " (blank) when false. Scoped to the
    /// matching section and occurrence, like `toggle`. Touches only that one
    /// byte. Throws if the line is not found as a checkbox line.
    public static func setInProgress(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        inProgress: Bool,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }

        var currentDate: String?
        var inFence = false
        var seen = 0
        for line in try markdownLines(in: data) {
            if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if line.text.hasPrefix("## ") {
                currentDate = TodoParser.sectionKey(fromHeading: line.text)
                continue
            }
            guard currentDate == sectionDate,
                  line.text == rawLine,
                  let boxIndex = checkboxIndex(in: data, lineRange: line.contentRange)
            else {
                continue
            }
            if seen < occurrence {
                seen += 1
                continue
            }

            var out = data
            out[boxIndex] = inProgress ? UInt8(ascii: "/") : UInt8(ascii: " ")
            return out
        }
        throw WritebackError.lineNotFound
    }

    /// Removes the exact line `rawLine` (with its line ending) only inside
    /// sections whose date matches `sectionDate`. `occurrence` selects among
    /// identical lines, matching TodoParser's occurrence numbering. Any
    /// indented description lines directly under the task go with it, so no
    /// orphaned note text is left behind. Touches nothing else in the file.
    /// Throws if the line is not found as a checkbox line in that section.
    public static func delete(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }

        let lines = try markdownLines(in: data)
        var currentDate: String?
        var inFence = false
        var seen = 0
        var index = lines.startIndex
        while index < lines.endIndex {
            let line = lines[index]
            if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                index += 1
                continue
            }
            if inFence { index += 1; continue }
            if line.text.hasPrefix("## ") {
                currentDate = TodoParser.sectionKey(fromHeading: line.text)
                index += 1
                continue
            }
            guard currentDate == sectionDate,
                  line.text == rawLine,
                  checkboxIndex(in: data, lineRange: line.contentRange) != nil
            else {
                index += 1
                continue
            }
            if seen < occurrence {
                seen += 1
                index += 1
                continue
            }

            var end = line.fullRange.upperBound
            var k = index + 1
            while k < lines.endIndex, TodoParser.isDescriptionLine(lines[k].text) {
                end = lines[k].fullRange.upperBound
                k += 1
            }
            var out = data
            out.removeSubrange(line.fullRange.lowerBound..<end)
            return out
        }
        throw WritebackError.lineNotFound
    }

    /// Sets (or clears) the description under the matched task. `note` is
    /// written as indented lines directly below the task, one per "\n". An
    /// empty note removes any existing description block. Replaces whatever
    /// description was there, and touches nothing else. Throws if the line
    /// is not found as a checkbox line in that section.
    public static func setNote(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        note: String,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }

        let lines = try markdownLines(in: data)
        let newline = preferredNewline(in: lines, data: data)
        var currentDate: String?
        var inFence = false
        var seen = 0
        var index = lines.startIndex
        while index < lines.endIndex {
            let line = lines[index]
            if line.text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                index += 1
                continue
            }
            if inFence { index += 1; continue }
            if line.text.hasPrefix("## ") {
                currentDate = TodoParser.sectionKey(fromHeading: line.text)
                index += 1
                continue
            }
            guard currentDate == sectionDate,
                  line.text == rawLine,
                  checkboxIndex(in: data, lineRange: line.contentRange) != nil
            else {
                index += 1
                continue
            }
            if seen < occurrence {
                seen += 1
                index += 1
                continue
            }

            // Existing description block: indented lines right below the task.
            var blockEnd = line.fullRange.upperBound
            var k = index + 1
            while k < lines.endIndex, TodoParser.isDescriptionLine(lines[k].text) {
                blockEnd = lines[k].fullRange.upperBound
                k += 1
            }

            let indent = String(rawLine.prefix { $0 == " " || $0 == "\t" }) + "    "
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            var insertion = Data()
            if !trimmed.isEmpty {
                // Task line had no trailing newline (last line of file): add one
                // before the note so the block sits on its own lines.
                if line.contentRange.upperBound == line.fullRange.upperBound {
                    insertion.append(newline)
                }
                for noteLine in trimmed.components(separatedBy: "\n") {
                    let clean = noteLine.trimmingCharacters(in: .whitespaces)
                    insertion.append(Data((indent + clean).utf8))
                    insertion.append(newline)
                }
            }

            var out = data
            out.replaceSubrange(line.fullRange.upperBound..<blockEnd, with: insertion)
            return out
        }
        throw WritebackError.lineNotFound
    }

    /// Appends "- [ ] title" to the end of today's section, creating the
    /// section at the end of the file if it doesn't exist yet.
    public static func append(title: String, today: String, in data: Data) throws -> Data {
        let lines = try markdownLines(in: data)
        let newline = preferredNewline(in: lines, data: data)
        let taskLine = "- [ ] " + title

        var headingIndex: Int?
        var nextHeadingIndex: Int?
        var inFence = false
        for index in lines.indices {
            let line = lines[index].text
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence || !line.hasPrefix("## ") { continue }

            if headingIndex != nil {
                nextHeadingIndex = index
                break
            }
            if line.firstMatch(of: TodoParser.dateRegex).map({
                String($0.0) == today
            }) ?? false {
                headingIndex = index
            }
        }

        guard let headingIndex else {
            return appendingNewSection(
                titleLine: taskLine,
                today: today,
                newline: newline,
                to: data
            )
        }

        var insertIndex = nextHeadingIndex ?? lines.endIndex
        while insertIndex > headingIndex + 1 && lines[insertIndex - 1].text.isEmpty {
            insertIndex -= 1
        }

        let offset = insertIndex < lines.endIndex
            ? lines[insertIndex].contentRange.lowerBound
            : data.endIndex
        var insertion = Data()
        if offset > data.startIndex && !isLineEnding(data[data.index(before: offset)]) {
            insertion.append(newline)
        }
        insertion.append(Data(taskLine.utf8))
        insertion.append(newline)

        var out = data
        out.insert(contentsOf: insertion, at: offset)
        return out
    }

    private static func checkboxIndex(
        in data: Data, lineRange: Range<Data.Index>
    ) -> Data.Index? {
        let marker = Data("- [".utf8)
        guard let m = data.range(of: marker, in: lineRange) else { return nil }
        let idx = m.upperBound
        guard idx < lineRange.upperBound else { return nil }
        let b = data[idx]
        let valid = b == UInt8(ascii: " ") || b == UInt8(ascii: "x")
            || b == UInt8(ascii: "X") || b == UInt8(ascii: "/")
        return valid ? idx : nil
    }

    private struct MarkdownLine {
        let contentRange: Range<Data.Index>
        let fullRange: Range<Data.Index>
        let text: String
    }

    private static func markdownLines(in data: Data) throws -> [MarkdownLine] {
        guard String(data: data, encoding: .utf8) != nil else {
            throw WritebackError.badEncoding
        }

        var lines: [MarkdownLine] = []
        var lineStart = data.startIndex
        var index = lineStart

        while index < data.endIndex {
            guard isLineEnding(data[index]) else {
                index = data.index(after: index)
                continue
            }

            let contentEnd = index
            var lineEnd = data.index(after: index)
            if data[index] == UInt8(ascii: "\r"),
               lineEnd < data.endIndex,
               data[lineEnd] == UInt8(ascii: "\n") {
                lineEnd = data.index(after: lineEnd)
            }
            lines.append(MarkdownLine(
                contentRange: lineStart..<contentEnd,
                fullRange: lineStart..<lineEnd,
                text: String(data: data[lineStart..<contentEnd], encoding: .utf8) ?? ""
            ))
            lineStart = lineEnd
            index = lineEnd
        }

        if lineStart < data.endIndex {
            lines.append(MarkdownLine(
                contentRange: lineStart..<data.endIndex,
                fullRange: lineStart..<data.endIndex,
                text: String(data: data[lineStart..<data.endIndex], encoding: .utf8) ?? ""
            ))
        }
        return lines
    }

    private static func preferredNewline(in lines: [MarkdownLine], data: Data) -> Data {
        for line in lines where line.fullRange.upperBound > line.contentRange.upperBound {
            return Data(data[line.contentRange.upperBound..<line.fullRange.upperBound])
        }
        return Data([UInt8(ascii: "\n")])
    }

    private static func appendingNewSection(
        titleLine: String,
        today: String,
        newline: Data,
        to data: Data
    ) -> Data {
        var out = data
        if hasContentBeyondBOM(data) {
            let trailingNewlines = trailingNewlineCount(in: data)
            if trailingNewlines == 0 { out.append(newline) }
            if trailingNewlines < 2 { out.append(newline) }
        }
        out.append(Data(("## " + today).utf8))
        out.append(newline)
        out.append(Data(titleLine.utf8))
        out.append(newline)
        return out
    }

    private static func hasContentBeyondBOM(_ data: Data) -> Bool {
        let bom = Data([0xEF, 0xBB, 0xBF])
        return !data.isEmpty && data != bom
    }

    private static func trailingNewlineCount(in data: Data) -> Int {
        var count = 0
        var index = data.endIndex
        while index > data.startIndex {
            let previous = data.index(before: index)
            if data[previous] == UInt8(ascii: "\n") {
                index = previous
                if index > data.startIndex {
                    let possibleCR = data.index(before: index)
                    if data[possibleCR] == UInt8(ascii: "\r") {
                        index = possibleCR
                    }
                }
                count += 1
            } else if data[previous] == UInt8(ascii: "\r") {
                index = previous
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func isLineEnding(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }
}
