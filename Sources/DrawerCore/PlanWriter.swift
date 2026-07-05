import Foundation

/// One entry in a day plan. `taskID` is set when this is an existing task
/// (`TodoItem.id`); nil for a brand-new suggested task. `minutes` writes a
/// `(Nm)` hint; `note` writes indented description lines.
public struct PlanEntry: Equatable, Sendable {
    public let title: String
    public let minutes: Int?
    public let note: String?
    public let taskID: String?

    public init(title: String, minutes: Int? = nil, note: String? = nil, taskID: String? = nil) {
        self.title = title
        self.minutes = minutes
        self.note = note
        self.taskID = taskID
    }
}

public enum PlanWriterError: Error, Equatable {
    case emptyPlan
    case tooManyEntries(Int)
    case tooManyNewTasks
    case unresolvedTaskID(String)
    case badEncoding
}

/// The single commit path for a day plan, shared by the in-app planner (spec
/// 03) and the MCP `write_day_plan` tool (spec 01). Neither has to know how the
/// markdown is edited, and structural validation runs on every caller so the
/// MCP path (no human preview card) still cannot write a malformed plan.
///
/// ponytail: works at the line level (decode, edit the target section, re-emit
/// with the file's dominant newline), not byte-surgical like TodoWriteback,
/// because creating/replacing a whole day section is a section-level edit. A
/// file that mixes CR and LF endings would be normalized to one style; Drawer.md
/// is always single-style in practice.
public enum PlanWriter {
    public static let maxEntries = 12

    public static func write(
        date: String,
        entries: [PlanEntry],
        replace: Bool = false,
        in data: Data
    ) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PlanWriterError.badEncoding
        }
        try validate(entries: entries, text: text)

        let sections = TodoParser.parse(text)
        let target = sections.first { $0.date == date }
        let keptTitles: Set<String> = {
            guard let target else { return [] }
            let kept = replace ? target.items.filter { $0.isDone || $0.isInProgress } : target.items
            return Set(kept.map { TitleSimilarity.normalize($0.title) })
        }()

        let blocks = entries
            .filter { !keptTitles.contains(TitleSimilarity.normalize($0.title)) }
            .flatMap(render)

        // Nothing to add and nothing to remove: leave the bytes untouched.
        if blocks.isEmpty, !replace { return data }

        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)

        if let bounds = sectionBounds(for: date, in: lines) {
            lines = editExisting(
                lines: lines, bounds: bounds, blocks: blocks, replace: replace
            )
        } else {
            lines = insertNewSection(date: date, blocks: blocks, into: lines)
        }
        return Data(lines.joined(separator: newline).utf8)
    }

    // MARK: validation

    private static func validate(entries: [PlanEntry], text: String) throws {
        guard !entries.isEmpty else { throw PlanWriterError.emptyPlan }
        guard entries.count <= maxEntries else {
            throw PlanWriterError.tooManyEntries(entries.count)
        }
        let sections = TodoParser.parse(text)
        let existingIDs = Set(sections.flatMap(\.items).map(\.id))
        let existingTitles = Set(sections.flatMap(\.items).map { TitleSimilarity.normalize($0.title) })

        var newTasks = 0
        for entry in entries {
            if let id = entry.taskID {
                guard existingIDs.contains(id) else {
                    throw PlanWriterError.unresolvedTaskID(id)
                }
                continue // resolves to an existing task
            }
            if !existingTitles.contains(TitleSimilarity.normalize(entry.title)) {
                newTasks += 1
            }
        }
        guard newTasks <= 1 else { throw PlanWriterError.tooManyNewTasks }
    }

    // MARK: rendering

    private static func render(_ entry: PlanEntry) -> [String] {
        var title = entry.title
        if let m = entry.minutes { title += " (\(m)m)" }
        var out = ["- [ ] " + title]
        if let note = entry.note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                for line in trimmed.components(separatedBy: "\n") {
                    out.append("    " + line.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return out
    }

    // MARK: section editing

    /// Half-open line range of a section's body (excluding its heading), plus
    /// the heading index. nil when the date section is absent.
    private struct SectionBounds {
        let heading: Int
        let bodyEnd: Int // first line index past the body (next heading or EOF)
    }

    private static func sectionBounds(for date: String, in lines: [String]) -> SectionBounds? {
        var inFence = false
        var heading: Int?
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle(); continue
            }
            if inFence || !line.hasPrefix("## ") { continue }
            if let h = heading {
                return SectionBounds(heading: h, bodyEnd: i)
            }
            if TodoParser.sectionKey(fromHeading: line) == date { heading = i }
        }
        return heading.map { SectionBounds(heading: $0, bodyEnd: lines.count) }
    }

    private static func editExisting(
        lines: [String], bounds: SectionBounds, blocks: [String], replace: Bool
    ) -> [String] {
        var body = Array(lines[(bounds.heading + 1)..<bounds.bodyEnd])
        if replace { body = dropUncheckedTasks(body) }

        // Append new blocks after the last non-blank body line.
        var insertAt = body.count
        while insertAt > 0, body[insertAt - 1].isEmpty { insertAt -= 1 }
        body.insert(contentsOf: blocks, at: insertAt)

        var out = Array(lines[0..<(bounds.heading + 1)])
        out.append(contentsOf: body)
        out.append(contentsOf: lines[bounds.bodyEnd...])
        return out
    }

    /// Removes blank-unchecked (`- [ ]`) task lines and their indented note
    /// lines. Checked (`- [x]`) and in-progress (`- [/]`) tasks stay, so done
    /// and actively-worked items are never erased.
    private static func dropUncheckedTasks(_ body: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < body.count {
            if marker(of: body[i]) == " " {
                i += 1
                while i < body.count, TodoParser.isDescriptionLine(body[i]) { i += 1 }
                continue
            }
            out.append(body[i])
            i += 1
        }
        return out
    }

    private static func insertNewSection(
        date: String, blocks: [String], into lines: [String]
    ) -> [String] {
        let section = ["## " + date] + blocks
        guard let at = insertionHeadingIndex(for: date, in: lines) else {
            // Append after all existing content.
            var trimmed = lines
            while let last = trimmed.last, last.isEmpty { trimmed.removeLast() }
            if trimmed.isEmpty { return section + [""] }
            return trimmed + [""] + section + [""]
        }
        return Array(lines[0..<at]) + section + [""] + Array(lines[at...])
    }

    /// Index of the first heading a new `date` section should precede: a later
    /// date, Backlog/Archive, or any non-date section. nil = append at the end.
    private static func insertionHeadingIndex(for date: String, in lines: [String]) -> Int? {
        var inFence = false
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle(); continue
            }
            if inFence || !line.hasPrefix("## ") { continue }
            guard let key = TodoParser.sectionKey(fromHeading: line) else { return i }
            if TodoParser.isValidDate(key) {
                if key > date { return i }
            } else {
                return i // Backlog / Archive
            }
        }
        return nil
    }

    /// The checkbox marker of a task line (` `, `x`, `X`, `/`), nil if the line
    /// is not a task line.
    private static func marker(of line: String) -> Character? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard trimmed.hasPrefix("- ["), trimmed.count >= 5 else { return nil }
        let box = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)]
        let close = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)]
        let valid: Set<Character> = [" ", "x", "X", "/"]
        return (valid.contains(box) && close == "]") ? box : nil
    }
}
