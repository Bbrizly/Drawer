import Foundation

public enum TodoParser {
    /// First YYYY-MM-DD anywhere in a "## " heading counts as the section
    /// date, so "## Mon 2026-06-08" works. A "## " heading with no date
    /// (or an impossible one like 2026-13-99) ends the current date section.
    static let dateRegex = #/\d{4}-\d{2}-\d{2}/#
    // "/" marks an in-progress task, the same glyph Obsidian uses.
    private static let taskRegex = #/^\s*- \[([ xX/])\] (.*)$/#
    private static let durationRegex = #/\((\d+)m\)\s*$/#

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
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return text.wholeMatch(of: taskRegex) == nil
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
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
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
            guard let date = currentDate, let m = line.wholeMatch(of: taskRegex) else {
                i += 1
                continue
            }
            let marker = String(m.1)
            let isDone = marker.lowercased() == "x"
            let isInProgress = marker == "/"
            let fullTitle = String(m.2)
            var minutes = 25
            var title = fullTitle
            if let dm = fullTitle.firstMatch(of: durationRegex),
               let n = Int(dm.1), (1...480).contains(n) {
                minutes = n
                title = String(fullTitle[..<dm.range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
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
        // ISO dates compare correctly as strings
        let nearestEarlier = days.map(\.date).filter { $0 < today }.max()
        let carried = nearestEarlier.map { earlier in
            days.filter { $0.date == earlier }
                .flatMap(\.items)
                .filter { !$0.isDone }
        } ?? []
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
