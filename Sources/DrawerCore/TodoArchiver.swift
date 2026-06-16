import Foundation

/// Moves finished tasks out of the day list once they are old enough.
///
/// A done task (`- [x]`) under a dated heading older than `keepDays` days
/// before `today` is moved into the "## Archive" section, under a "### Done"
/// subheading. Its indented note lines travel with it. The transform is a
/// pure function on the file text so it is easy to test, and it is
/// idempotent: archived tasks live under "## Archive" (not a date), so a
/// second pass finds nothing to move.
public enum TodoArchiver {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.isLenient = false
        return f
    }()

    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Returns the text with old done tasks moved into Archive > Done. Returns
    /// the input unchanged when nothing qualifies, when `today` is not a valid
    /// date, or when `keepDays` is negative.
    public static func archiveCompleted(
        in text: String, today: String, keepDays: Int = 3
    ) -> String {
        guard keepDays >= 0,
              let todayDate = formatter.date(from: today),
              let cutoffDate = utcCalendar.date(byAdding: .day, value: -keepDays, to: todayDate)
        else { return text }
        let cutoff = formatter.string(from: cutoffDate)

        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        // omittingEmptySubsequences:false keeps blank lines and any trailing
        // empty line, so a join with `newline` reproduces the file exactly.
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)

        // Phase 1: find done-task blocks under dated sections older than cutoff.
        var blocksToMove: [[String]] = []
        var indicesToRemove = Set<Int>()
        var currentKey: String?
        var inFence = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle(); i += 1; continue
            }
            if inFence { i += 1; continue }
            if line.hasPrefix("## ") {
                currentKey = TodoParser.sectionKey(fromHeading: line)
                i += 1; continue
            }
            // Only sweep real dated sections strictly older than the cutoff.
            guard let key = currentKey,
                  TodoParser.isValidDate(key), key < cutoff,
                  isDoneTask(line)
            else { i += 1; continue }

            // Gather the task line plus its indented note lines.
            var block = [line]
            indicesToRemove.insert(i)
            var j = i + 1
            while j < lines.count, TodoParser.isDescriptionLine(lines[j]) {
                block.append(lines[j])
                indicesToRemove.insert(j)
                j += 1
            }
            blocksToMove.append(block)
            i = j
        }

        guard !blocksToMove.isEmpty else { return text }

        // Phase 2: drop moved lines, then splice the blocks into Archive > Done.
        let kept = lines.enumerated()
            .filter { !indicesToRemove.contains($0.offset) }
            .map(\.element)
        let movedLines = blocksToMove.flatMap { $0 }
        let rebuilt = insertIntoArchiveDone(movedLines, into: kept)
        return rebuilt.joined(separator: newline)
    }

    private static func isDoneTask(_ line: String) -> Bool {
        guard let m = line.wholeMatch(of: #/^\s*- \[([ xX/])\] (.*)$/#) else { return false }
        let marker = String(m.1).lowercased()
        return marker == "x"
    }

    /// Inserts `moved` lines under "## Archive" > "### Done", creating either
    /// heading if missing. Keeps existing Archive content in place.
    private static func insertIntoArchiveDone(
        _ moved: [String], into lines: [String]
    ) -> [String] {
        guard !moved.isEmpty else { return lines }

        // Locate the Archive section bounds (heading line .. next "## ").
        var archiveStart: Int?
        var archiveEnd = lines.count
        var inFence = false
        for idx in lines.indices {
            let line = lines[idx]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle(); continue
            }
            if inFence || !line.hasPrefix("## ") { continue }
            if archiveStart != nil { archiveEnd = idx; break }
            if TodoParser.sectionKey(fromHeading: line) == TodoParser.archiveKey {
                archiveStart = idx
            }
        }

        guard let start = archiveStart else {
            // No Archive section: append one at the end of the file.
            var out = lines
            // Drop a single trailing empty line so spacing stays tidy; it is
            // restored by the join when we re-add a trailing entry below.
            let hadTrailing = out.last == ""
            if hadTrailing { out.removeLast() }
            if let last = out.last, !last.isEmpty { out.append("") }
            out.append("## Archive")
            out.append("")
            out.append("### Done")
            out.append(contentsOf: moved)
            if hadTrailing { out.append("") }
            return out
        }

        // Find "### Done" within the Archive section.
        var doneHeading: Int?
        for idx in (start + 1)..<archiveEnd where
            lines[idx].trimmingCharacters(in: .whitespaces).lowercased() == "### done" {
            doneHeading = idx
            break
        }

        var out = lines
        if let done = doneHeading {
            // Insert at the end of the Done subgroup (before the next "###"/"##").
            var insertAt = done + 1
            while insertAt < archiveEnd,
                  !out[insertAt].hasPrefix("### "),
                  !out[insertAt].hasPrefix("## ") {
                insertAt += 1
            }
            // Step back over trailing blank lines so the block sits snug.
            while insertAt > done + 1, out[insertAt - 1].isEmpty { insertAt -= 1 }
            out.insert(contentsOf: moved, at: insertAt)
        } else {
            // Create the Done subgroup right under the Archive heading.
            out.insert(contentsOf: ["### Done"] + moved, at: start + 1)
        }
        return out
    }
}
