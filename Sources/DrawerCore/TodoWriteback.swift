import Foundation

public enum WritebackError: Error, Equatable {
    case lineNotFound
    case badEncoding
}

/// Where a command means to land. Section plus position plus the text the line
/// had when the user acted, so a command can still find its task after an
/// earlier queued command has changed that text.
public struct TodoTarget: Sendable, Equatable {
    /// The section to search, or nil to match anywhere in the file.
    public let sectionKey: String?
    /// The line exactly as the user saw it.
    public let rawLine: String
    /// Position among the section's task lines when the user acted, or nil when
    /// the caller only knows the text.
    public let ordinal: Int?
    /// Index among identical `rawLine`s in the section (0 = first).
    public let occurrence: Int
    /// The bytes being edited are exactly what this app last wrote, so a line
    /// that no longer reads like `rawLine` was changed by an earlier queued
    /// command and not by an outside editor. Only then may `ordinal` win over
    /// the text: that is what makes a second toggle land on the task the first
    /// one just checked instead of failing to find the old line.
    public let trustsOrdinal: Bool

    public init(
        sectionKey: String?,
        rawLine: String,
        ordinal: Int? = nil,
        occurrence: Int = 0,
        trustsOrdinal: Bool = false
    ) {
        self.sectionKey = sectionKey
        self.rawLine = rawLine
        self.ordinal = ordinal
        self.occurrence = occurrence
        self.trustsOrdinal = trustsOrdinal
    }

    public func trusting(_ flag: Bool) -> TodoTarget {
        TodoTarget(
            sectionKey: sectionKey, rawLine: rawLine, ordinal: ordinal,
            occurrence: occurrence, trustsOrdinal: flag)
    }
}

public enum TodoWriteback {
    /// Flips the checkbox on the exact line `rawLine` inside `data`,
    /// touching only that single byte. Throws if the line is not found
    /// as a complete line (bounded by newlines or file edges).
    public static func toggle(line rawLine: String, in data: Data) throws -> Data {
        try toggle(target: TodoTarget(sectionKey: nil, rawLine: rawLine), in: data)
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
        try toggle(
            target: TodoTarget(
                sectionKey: sectionDate, rawLine: rawLine, occurrence: occurrence),
            in: data)
    }

    public static func toggle(target: TodoTarget, in data: Data) throws -> Data {
        let (lines, _, index) = try find(target, in: data)
        guard let boxIndex = checkboxIndex(in: data, lineRange: lines[index].contentRange) else {
            throw WritebackError.lineNotFound
        }
        var out = data
        // Checking a blank or in-progress "/" task completes it. Only an
        // already-done task toggles back to blank.
        let done = out[boxIndex] == UInt8(ascii: "x") || out[boxIndex] == UInt8(ascii: "X")
        out[boxIndex] = done ? UInt8(ascii: " ") : UInt8(ascii: "x")
        return out
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
        try setInProgress(
            target: TodoTarget(
                sectionKey: sectionDate, rawLine: rawLine, occurrence: occurrence),
            inProgress: inProgress, in: data)
    }

    public static func setInProgress(
        target: TodoTarget, inProgress: Bool, in data: Data
    ) throws -> Data {
        let (lines, _, index) = try find(target, in: data)
        guard let boxIndex = checkboxIndex(in: data, lineRange: lines[index].contentRange) else {
            throw WritebackError.lineNotFound
        }
        var out = data
        out[boxIndex] = inProgress ? UInt8(ascii: "/") : UInt8(ascii: " ")
        return out
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
        try delete(
            target: TodoTarget(
                sectionKey: sectionDate, rawLine: rawLine, occurrence: occurrence),
            in: data)
    }

    public static func delete(target: TodoTarget, in data: Data) throws -> Data {
        let (lines, roles, index) = try find(target, in: data)
        var out = data
        out.removeSubrange(lines[index].fullRange.lowerBound..<noteBlockEnd(index, lines, roles))
        return out
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
        try setNote(
            target: TodoTarget(
                sectionKey: sectionDate, rawLine: rawLine, occurrence: occurrence),
            note: note, in: data)
    }

    public static func setNote(target: TodoTarget, note: String, in data: Data) throws -> Data {
        let (lines, roles, index) = try find(target, in: data)
        let line = lines[index]
        let newline = preferredNewline(in: lines, data: data)
        let blockEnd = noteBlockEnd(index, lines, roles)

        let indent = String(line.text.prefix { $0 == " " || $0 == "\t" }) + "    "
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

    /// Appends "- [ ] title" to the end of today's section, creating the
    /// section at the end of the file if it doesn't exist yet.
    public static func append(title: String, today: String, in data: Data) throws -> Data {
        let lines = try markdownLines(in: data)
        let newline = preferredNewline(in: lines, data: data)
        let taskLine = "- [ ] " + title

        var headingIndex: Int?
        var nextHeadingIndex: Int?
        let roles = TodoParser.lineRoles(lines.map(\.text))
        for index in lines.indices where roles[index] == .heading {
            let line = lines[index].text
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

    /// Inserts a raw line (a "- [ ] task" or a "### header") at the end of the
    /// section whose key matches `sectionKey` (a date, "backlog", or "archive").
    /// Creates the section with `## displayHeading` at the end of the file if it
    /// is missing. Same insertion logic as `append(title:today:)` -- that path
    /// is battle-tested and I didn't want to touch it.
    public static func insert(
        line newLine: String,
        intoSectionKey sectionKey: String,
        displayHeading: String,
        in data: Data
    ) throws -> Data {
        let lines = try markdownLines(in: data)
        let newline = preferredNewline(in: lines, data: data)

        var headingIndex: Int?
        var nextHeadingIndex: Int?
        let roles = TodoParser.lineRoles(lines.map(\.text))
        for index in lines.indices where roles[index] == .heading {
            let text = lines[index].text
            if headingIndex != nil { nextHeadingIndex = index; break }
            if TodoParser.sectionKey(fromHeading: text) == sectionKey { headingIndex = index }
        }

        guard let headingIndex else {
            var out = data
            if hasContentBeyondBOM(data) {
                let trailing = trailingNewlineCount(in: data)
                if trailing == 0 { out.append(newline) }
                if trailing < 2 { out.append(newline) }
            }
            out.append(Data(("## " + displayHeading).utf8))
            out.append(newline)
            out.append(Data(newLine.utf8))
            out.append(newline)
            return out
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
        insertion.append(Data(newLine.utf8))
        insertion.append(newline)

        var out = data
        out.insert(contentsOf: insertion, at: offset)
        return out
    }

    /// Replaces the title text of the matched checkbox line with `newTitle`,
    /// preserving indentation and the checkbox state. Any "(15m)" duration hint
    /// that was part of the old title is dropped. Scoped by section + occurrence
    /// like the others. Throws if the line is not found as a checkbox line.
    public static func rename(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        to newTitle: String,
        in data: Data
    ) throws -> Data {
        try rename(
            target: TodoTarget(
                sectionKey: sectionDate, rawLine: rawLine, occurrence: occurrence),
            to: newTitle, in: data)
    }

    public static func rename(target: TodoTarget, to newTitle: String, in data: Data) throws -> Data {
        let (lines, _, index) = try find(target, in: data)
        let line = lines[index]
        guard let boxIndex = checkboxIndex(in: data, lineRange: line.contentRange) else {
            throw WritebackError.lineNotFound
        }
        // boxIndex points at the state char; "]" then " " then the title.
        let bracket = data.index(after: boxIndex)
        guard bracket < line.contentRange.upperBound,
              data[bracket] == UInt8(ascii: "]")
        else { throw WritebackError.lineNotFound }
        var titleStart = data.index(after: bracket)
        if titleStart < line.contentRange.upperBound, data[titleStart] == UInt8(ascii: " ") {
            titleStart = data.index(after: titleStart)
        }
        var out = data
        out.replaceSubrange(titleStart..<line.contentRange.upperBound, with: Data(newTitle.utf8))
        return out
    }

    /// The one place a command turns into a line index. Two ways in, and which
    /// one wins is the whole point: normally the exact text plus occurrence, as
    /// it always was, but when the file is untouched since our own last write a
    /// trusted ordinal wins instead. That is what lets a second command queued
    /// on the same row land, when the first has already rewritten the text the
    /// second is holding. When an outside editor is in play the ordinal is not
    /// trusted, so a vanished line still fails rather than hitting its neighbour.
    private static func find(
        _ target: TodoTarget, in data: Data
    ) throws -> ([MarkdownLine], [TodoParser.LineRole], Int) {
        guard !target.rawLine.isEmpty else { throw WritebackError.lineNotFound }
        let lines = try markdownLines(in: data)
        // The parser's own per-line classification, so fence and note handling
        // can never disagree with what the task list displays.
        let roles = TodoParser.lineRoles(lines.map(\.text))

        var currentKey: String?
        var tasks: [Int] = []
        var matches: [Int] = []
        for i in lines.indices {
            if roles[i] == .fence || roles[i] == .fenced { continue }
            if roles[i] == .heading {
                // Shared with the parser so section boundaries always agree
                // (dates and the "backlog" key alike).
                currentKey = TodoParser.sectionKey(fromHeading: lines[i].text)
                continue
            }
            guard target.sectionKey == nil || currentKey == target.sectionKey,
                  checkboxIndex(in: data, lineRange: lines[i].contentRange) != nil
            else { continue }
            tasks.append(i)
            if lines[i].text == target.rawLine { matches.append(i) }
        }

        if target.trustsOrdinal, let ordinal = target.ordinal, tasks.indices.contains(ordinal) {
            return (lines, roles, tasks[ordinal])
        }
        guard target.occurrence < matches.count else { throw WritebackError.lineNotFound }
        return (lines, roles, matches[target.occurrence])
    }

    /// End of the task line plus the indented description block under it.
    private static func noteBlockEnd(
        _ index: Int, _ lines: [MarkdownLine], _ roles: [TodoParser.LineRole]
    ) -> Data.Index {
        var end = lines[index].fullRange.upperBound
        var k = index + 1
        while k < lines.endIndex, roles[k] == .note {
            end = lines[k].fullRange.upperBound
            k += 1
        }
        return end
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
