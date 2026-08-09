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

    /// A ``` line, front-trimmed without allocating a trimmed copy per line.
    static func isFenceLine(_ line: some StringProtocol) -> Bool {
        line.drop { $0 == " " || $0 == "\t" }.hasPrefix("```")
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
    /// under a task, form that task's note. Shared with TodoWriteback so
    /// reading and editing agree on where a note starts and ends.
    static func isDescriptionLine(_ text: String) -> Bool {
        guard let first = text.first, first == " " || first == "\t" else { return false }
        if text.allSatisfy(\.isWhitespace) { return false }
        return taskParts(text) == nil
    }

    /// Per-line classification, produced with the exact fence and
    /// note-consumption rules of `parse`. Writers consult this instead of
    /// tracking fences themselves, so an edit can never disagree with what
    /// the parser displays (an indented ``` under a task is note text, not a
    /// fence, for example -- treating it as a fence once let a replace run
    /// past the next heading and delete another day's tasks).
    enum LineRole: Equatable {
        case fence   // a ``` line that toggles fence state
        case fenced  // inside an open fence
        case heading // a "## " section heading
        case task    // a checkbox line in a keyed (date/backlog/archive) section
        case note    // indented description line consumed by the task above
        case plain   // anything else
    }

    static func lineRoles(_ lines: [String]) -> [LineRole] {
        var roles = [LineRole](repeating: .plain, count: lines.count)
        var currentKey: String?
        var inFence = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isFenceLine(line) {
                roles[i] = .fence
                inFence.toggle()
                i += 1
                continue
            }
            if inFence { roles[i] = .fenced; i += 1; continue }
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
        var occurrences: [String: Int] = [:] // date + "|" + rawLine
        var currentDate: String?
        var currentSubsection: String?
        var inFence = false

        // Split on Character.isNewline: "\r\n" is a single grapheme in Swift,
        // so splitting on "\n" alone would never split CRLF files.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isFenceLine(line) {
                inFence.toggle()
                i += 1
                continue
            }
            if inFence { i += 1; continue }
            if line.hasPrefix("## ") {
                currentSubsection = nil // subheadings don't outlive their section
                if let key = sectionKey(fromHeading: line) {
                    currentDate = key
                    if itemsByDate[key] == nil {
                        itemsByDate[key] = []
                        order.append(key)
                    }
                } else {
                    currentDate = nil // non-date section: tasks below are not day tasks
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
            // Indented lines right below the task are its description.
            var noteLines: [String] = []
            var j = i + 1
            while j < lines.count, isDescriptionLine(lines[j]) {
                noteLines.append(lines[j].trimmingCharacters(in: .whitespaces))
                j += 1
            }
            let note = noteLines.isEmpty ? nil : noteLines.joined(separator: "\n")
            let occurrenceKey = date + "|" + line
            let occurrence = occurrences[occurrenceKey, default: 0]
            occurrences[occurrenceKey] = occurrence + 1
            itemsByDate[date, default: []].append(TodoItem(
                rawLine: line, title: title, isDone: isDone,
                isInProgress: isInProgress,
                minutes: minutes, sectionDate: date, occurrence: occurrence,
                subsection: currentSubsection, note: note
            ))
            i = j // skip the consumed description lines
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
        // Backlog/Archive are not days; keep them out of the date
        // comparisons below ("backlog" > "2026-..." as a string and would
        // fake a Tomorrow).
        let days = sections.filter { isValidDate($0.date) }
        let backlog = sections.filter { $0.date == backlogKey }.flatMap(\.items)
        let archive = sections.filter { $0.date == archiveKey }.flatMap(\.items)

        let todayItems = days.filter { $0.date == today }.flatMap(\.items)
        // Carry every unfinished task from ALL earlier days, oldest first.
        // Taking only the nearest earlier day silently dropped anything left
        // open on older days the moment a newer day section appeared.
        // ISO dates compare and sort correctly as strings.
        let carried = days
            .filter { $0.date < today }
            .sorted { $0.date < $1.date }
            .flatMap(\.items)
            .filter { !$0.isDone }
        // Next planned day, so an evening glance shows tomorrow's list.
        // Includes checked items: hiding completed is the view's job
        // (the "Hide completed" toggle), not a display-rule decision.
        let nearestUpcoming = days.map(\.date).filter { $0 > today }.min()
        let upcoming = nearestUpcoming.map { next in
            days.filter { $0.date == next }.flatMap(\.items)
        } ?? []
        return (todayItems, carried, upcoming, nearestUpcoming, backlog, archive)
    }
}
