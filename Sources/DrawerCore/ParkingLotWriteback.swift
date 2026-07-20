import Foundation

/// Splices single-idea edits into the lot file, leaving every other line
/// byte-for-byte untouched. Same instinct as TodoWriteback: never
/// re-serialise the whole document, the file is the user's first.
public enum ParkingLotWriteback {
    /// Canonical lines for one idea: the bullet line, then detail lines
    /// indented four spaces. Blank detail lines are dropped because a blank
    /// line is what ends a note in this format.
    public static func serialize(
        title: String, details: String, parked: String?, color: String?
    ) -> [String] {
        let meta = [parked, color].compactMap { $0 }.joined(separator: " ")
        var lines = [meta.isEmpty ? "- \(title)" : "- \(title) (\(meta))"]
        for line in details.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("    " + line.trimmingCharacters(in: .whitespaces))
        }
        return lines
    }

    /// Replaces one idea's lines with fresh content. The parked date rides
    /// along unchanged; only the title, details, and colour are editable.
    public static func replace(
        _ idea: ParkedIdea, in text: String,
        title: String, details: String, color: String?
    ) -> String {
        splice(text, range: idea.lineRange,
               with: serialize(title: title, details: details, parked: idea.parked, color: color))
    }

    public static func delete(_ idea: ParkedIdea, in text: String) -> String {
        splice(text, range: idea.lineRange, with: [])
    }

    /// Appends an idea at the end of the named bay. A missing bay is created
    /// at the top of the file, which is where Unsorted lives.
    public static func append(
        title: String, details: String, parked: String?, color: String?,
        toBay bay: String, in text: String
    ) -> String {
        var lines = split(text)
        let ideaLines = serialize(title: title, details: details, parked: parked, color: color)
        if let h = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## \(bay)"
        }) {
            var end = h + 1
            while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
            // Back over the blank lines that separate this bay from the next.
            var at = end
            while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                at -= 1
            }
            lines.insert(contentsOf: ideaLines, at: at)
        } else {
            lines.insert(contentsOf: ["## \(bay)"] + ideaLines + [""], at: 0)
        }
        return lines.joined(separator: "\n")
    }

    static func split(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    static func splice(_ text: String, range: Range<Int>, with newLines: [String]) -> String {
        var lines = split(text)
        guard range.lowerBound >= 0, range.upperBound <= lines.count else { return text }
        lines.replaceSubrange(range, with: newLines)
        return lines.joined(separator: "\n")
    }
}
