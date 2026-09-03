import Foundation

public enum TodoParser {
    /// First YYYY-MM-DD anywhere in a "## " heading counts as the section
    /// date, so "## Mon 2026-06-08" works. A "## " heading with no date
    /// (or an impossible one like 2026-13-99) ends the current date section.
    static let dateRegex = #/\d{4}-\d{2}-\d{2}/#
    /// The `- [ ] title` shape, scanned by hand. A regex read better but ran
    /// far slower, and this runs over every line of the file on each parse and
    /// on each writeback (`lineRoles`), which a year of archive makes felt.
    /// "/" marks an in-progress task, the same glyph Obsidian uses.
    static func taskParts<S: StringProtocol>(
        _ line: S
    ) -> (marker: Character, title: Substring)? where S.SubSequence == Substring {
        var i = line.startIndex
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        guard line[i...].hasPrefix("- [") else { return nil }
        let markerAt = line.index(i, offsetBy: 3)
        guard markerAt < line.endIndex else { return nil }
        let marker = line[markerAt]
        guard marker == " " || marker == "x" || marker == "X" || marker == "/" else { return nil }
        let close = line.index(after: markerAt)
        guard line[close...].hasPrefix("] ") else { return nil }
        return (marker, line[line.index(close, offsetBy: 2)...])
    }

    /// Markdown fenced-code marker, front-trimmed without allocating a full
    /// trimmed copy per line. Both CommonMark fence forms are recognized.
    static func fenceMarker(_ line: some StringProtocol) -> Character? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    static func isFenceLine(_ line: some StringProtocol) -> Bool {
        fenceMarker(line) != nil
    }

    /// A trailing "(25m)" focus length: the minutes and where the title ends.
    /// Scanned backwards for the same reason `taskParts` is hand-rolled.
    static func duration(in title: Substring) -> (minutes: Int, titleEnd: Substring.Index)? {
        var i = title.endIndex
        while i > title.startIndex, title[title.index(before: i)].isWhitespace {
            i = title.index(before: i)
        }
        guard i > title.startIndex, title[title.index(before: i)] == ")" else { return nil }
        i = title.index(before: i)
        guard i > title.startIndex, title[title.index(before: i)] == "m" else { return nil }
        let digitsEnd = title.index(before: i)
        var digitsStart = digitsEnd
        while digitsStart > title.startIndex,
              let d = title[title.index(before: digitsStart)].wholeNumberValue, (0...9).contains(d) {
            digitsStart = title.index(before: digitsStart)
        }
        guard digitsStart < digitsEnd,
              digitsStart > title.startIndex,
              title[title.index(before: digitsStart)] == "(",
              let n = Int(title[digitsStart..<digitsEnd])
        else { return nil }
        return (n, title.index(before: digitsStart))
    }

    // DateFormatter is thread-safe for parsing since macOS 10.9.
    private static let dateValidator: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.isLenient = false
        return f
    }()

    /// True only for real calendar dates (rejects 2026-13-99 etc.).
    static func isValidDate(_ string: String) -> Bool {
        dateValidator.date(from: string) != nil
    }

    /// Sentinel section keys for the "## Backlog" and "## Archive"
    /// sections. Never collide with a date key since dates are always
    /// YYYY-MM-DD.
    public static let backlogKey = "backlog"
    public static let archiveKey = "archive"

    /// Extracts the section date from a "## " heading line, nil if the
    /// heading has no date or an invalid one. Shared with TodoWriteback so
    /// display and writeback agree on section boundaries.
    static func sectionDate(fromHeading line: String) -> String? {
        guard let match = line.firstMatch(of: dateRegex) else { return nil }
        let date = String(match.0)
        return isValidDate(date) ? date : nil
    }

    /// True for a description line: indented (leading space or tab), not
    /// blank, and not itself a checkbox task. These lines, sitting directly
    /// under a task, form that task's complete child block. Reserved Drawer
    /// metadata remains part of the block for lossless move/delete/archive,
    /// but is filtered from the human-facing note below.
    static func isDescriptionLine(_ text: String) -> Bool {
        guard let first = text.first, first == " " || first == "\t" else { return false }
        if text.allSatisfy(\.isWhitespace) { return false }
        return taskParts(text) == nil
    }

    static func isDrawerMetadataLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("<!-- drawer:")
    }

    /// Per-line classification, produced with the exact fence and
    /// note-consumption rules of `parse`. Writers consult this instead of
    /// tracking fences themselves, so an edit can never disagree with what
    /// the parser displays (an indented ``` under a task is note text, not a
    /// fence, for example -- treating it as a fence once let a replace run
    /// past the next heading and delete another day's tasks).
    enum LineRole: Equatable {
        case fence
        case fenced
        case heading
        case task
        case note
        case plain
    }

    static func lineRoles(_ lines: [String]) -> [LineRole] {
        var roles = [LineRole](repeating: .plain, count: lines.count)
        var currentKey: String?
        var activeFence: Character?
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let marker = fenceMarker(line) {
                if activeFence == nil {
                    activeFence = marker
                    roles[i] = .fence
                    i += 1
                    continue
                }
                if activeFence == marker {
                    activeFence = nil
                    roles[i] = .fence
                    i += 1
                    continue
                }
            }
            if activeFence != nil { roles[i] = .fenced; i += 1; continue }
            if line.hasPrefix("## ") {
                roles[i] = .heading
                currentKey = sectionKey(fromHeading: line)
                i += 1
                continue
            }
            guard currentKey != nil, taskParts(line) != nil else {
                i += 1
                continue
            }
            roles[i] = .task
            var j = i + 1
            while j < lines.count, isDescriptionLine(lines[j]) {
                roles[j] = .note
                j += 1
            }
            i = j
        }
        return roles
    }

    /// Section key for a "## " heading: its date, "backlog"/"archive" for
    /// headings titled exactly "Backlog"/"Archive" (any case), nil
    /// otherwise. Shared with TodoWriteback so toggle scoping agrees with
    /// display.
    static func sectionKey(fromHeading line: String) -> String? {
        if let date = sectionDate(fromHeading: line) { return date }
        let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
        return (title == backlogKey || title == archiveKey) ? title : nil
    }

    public static func parse(_ text: String) -> [DaySection] {
        var itemsByDate: [String: [TodoItem]] = [:]
        var order: [String] = []
        var occurrences: [String: Int] = [:]
        var ordinals: [String: Int] = [:]
        var currentDate: String?
        var currentSubsection: String?
        var activeFence: Character?

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if let marker = fenceMarker(line) {
                if activeFence == nil {
                    activeFence = marker
                    i += 1
                    continue
                }
                if activeFence == marker {
                    activeFence = nil
                    i += 1
                    continue
                }
            }
            if activeFence != nil { i += 1; continue }
            if line.hasPrefix("## ") {
                currentSubsection = nil
                if let key = sectionKey(fromHeading: line) {
                    currentDate = key
                    if itemsByDate[key] == nil {
                        itemsByDate[key] = []
                        order.append(key)
                    }
                } else {
                    currentDate = nil
                }
                i += 1
                continue
            }
            if line.hasPrefix("### ") {
                let title = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentSubsection = title.isEmpty ? nil : title
                i += 1
                continue
            }
            guard let date = currentDate, let m = taskParts(line) else {
                i += 1
                continue
            }
            let isDone = m.marker == "x" || m.marker == "X"
            let isInProgress = m.marker == "/"
            var minutes = 25
            var title = String(m.title)
            if let d = duration(in: m.title), (1...480).contains(d.minutes) {
                minutes = d.minutes
                title = String(m.title[..<d.titleEnd]).trimmingCharacters(in: .whitespaces)
            }
            var noteLines: [String] = []
            var j = i + 1
            while j < lines.count, isDescriptionLine(lines[j]) {
                if !isDrawerMetadataLine(lines[j]) {
                    noteLines.append(lines[j].trimmingCharacters(in: .whitespaces))
                }
                j += 1
            }
            let note = noteLines.isEmpty ? nil : noteLines.joined(separator: "\n")
            let occurrenceKey = date + "|" + line
            let occurrence = occurrences[occurrenceKey, default: 0]
            occurrences[occurrenceKey] = occurrence + 1
            let ordinal = ordinals[date, default: 0]
            ordinals[date] = ordinal + 1
            itemsByDate[date, default: []].append(TodoItem(
                rawLine: line, title: title, isDone: isDone,
                isInProgress: isInProgress,
                minutes: minutes, sectionDate: date, occurrence: occurrence,
                ordinal: ordinal, subsection: currentSubsection, note: note
            ))
            i = j
        }
        return order.map { DaySection(date: $0, items: itemsByDate[$0] ?? []) }
    }

    public static func display(
        sections: [DaySection], today: String
    ) -> (
        today: [TodoItem], carried: [TodoItem],
        upcoming: [TodoItem], upcomingDate: String?,
        backlog: [TodoItem], archive: [TodoItem]
    ) {
        let days = sections.filter { isValidDate($0.date) }
        let backlog = sections.filter { $0.date == backlogKey }.flatMap(\.items)
        let archive = sections.filter { $0.date == archiveKey }.flatMap(\.items)

        let todayItems = days.filter { $0.date == today }.flatMap(\.items)
        let carried = days
            .filter { $0.date < today }
            .sorted { $0.date < $1.date }
            .flatMap(\.items)
            .filter { !$0.isDone }
        let nearestUpcoming = days.map(\.date).filter { $0 > today }.min()
        let upcoming = nearestUpcoming.map { next in
            days.filter { $0.date == next }.flatMap(\.items)
        } ?? []
        return (todayItems, carried, upcoming, nearestUpcoming, backlog, archive)
    }
}
