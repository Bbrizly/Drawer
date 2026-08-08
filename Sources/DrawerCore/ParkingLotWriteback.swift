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
        // Matched on the parsed name, not the raw line: a coloured bay's
        // heading reads `## Apps (blue)` and still holds the ideas for "Apps".
        if let h = lines.firstIndex(where: {
            $0.hasPrefix("## ") && ParkingLotParser.bayHeading(heading($0)).name == bay
        }) {
            // Back over the blank lines that separate this bay from the next.
            var at = endOfBay(from: h, in: lines)
            while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                at -= 1
            }
            lines.insert(contentsOf: ideaLines, at: at)
        } else {
            lines.insert(contentsOf: ["## \(bay)"] + ideaLines + [""], at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Renames the nth bay by rewriting its heading line. The ideas under it
    /// keep their lines, so nothing has to be re-parked. The bay's colour is
    /// part of the heading, so it goes back on.
    public static func renameBay(at index: Int, to name: String, in text: String) -> String {
        var lines = split(text)
        guard let h = headingLine(at: index, in: lines) else { return text }
        let color = ParkingLotParser.bayHeading(heading(lines[h])).color
        lines[h] = heading(name: name, color: color)
        return lines.joined(separator: "\n")
    }

    /// Sets or clears the nth bay's colour token, leaving its name alone.
    public static func setBayColor(at index: Int, to color: String?, in text: String) -> String {
        var lines = split(text)
        guard let h = headingLine(at: index, in: lines) else { return text }
        let name = ParkingLotParser.bayHeading(heading(lines[h])).name
        lines[h] = heading(name: name, color: color)
        return lines.joined(separator: "\n")
    }

    /// Removes a bay heading and everything under it up to the next heading.
    /// The ideas go with it; that is what deleting a category means.
    public static func deleteBay(at index: Int, in text: String) -> String {
        var lines = split(text)
        guard let h = headingLine(at: index, in: lines) else { return text }
        lines.removeSubrange(h..<endOfBay(from: h, in: lines))
        return lines.joined(separator: "\n")
    }

    /// Moves a whole bay, heading and ideas, to another slot in file order.
    /// The lot renders in file order, so this is what reordering is.
    public static func moveBay(from index: Int, to destination: Int, in text: String) -> String {
        var lines = split(text)
        let count = lines.filter { $0.hasPrefix("## ") }.count
        guard index != destination, (0..<count).contains(index),
              (0..<count).contains(destination),
              let h = headingLine(at: index, in: lines) else { return text }
        let end = endOfBay(from: h, in: lines)
        // Carry the blank line that separates this bay from the next, so
        // moving never welds two bays together or leaves a double gap.
        var block = Array(lines[h..<end])
        while block.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { block.removeLast() }
        block.append("")
        lines.removeSubrange(h..<end)

        let remaining = lines.filter { $0.hasPrefix("## ") }.count
        let at: Int
        if destination >= remaining {
            at = lines.count
        } else {
            at = headingLine(at: destination, in: lines) ?? lines.count
        }
        lines.insert(contentsOf: block, at: at)
        return lines.joined(separator: "\n")
    }

    /// The nth `## ` line, or nil when the file has fewer bays than that.
    private static func headingLine(at index: Int, in lines: [String]) -> Int? {
        var seen = -1
        for (i, line) in lines.enumerated() where line.hasPrefix("## ") {
            seen += 1
            if seen == index { return i }
        }
        return nil
    }

    /// One past the last line belonging to the bay whose heading is at `h`.
    private static func endOfBay(from h: Int, in lines: [String]) -> Int {
        var end = h + 1
        while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
        return end
    }

    private static func heading(_ line: String) -> String {
        String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private static func heading(name: String, color: String?) -> String {
        guard let color else { return "## " + name }
        return "## \(name) (\(color))"
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
