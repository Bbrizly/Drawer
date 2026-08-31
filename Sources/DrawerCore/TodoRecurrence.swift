import Foundation

public enum TodoRecurrenceError: Error, Equatable {
    case invalidUTF8
    case taskNotFound
    case noRecurrence
    case invalidMetadata
    case duplicateActiveSeries
}

public enum TodoRecurrenceRule: Equatable, Sendable, Codable {
    case daily
    /// ISO weekday numbers: Monday = 1 ... Sunday = 7.
    case weekdays(Set<Int>)
    case everyDays(Int)
    case monthly(Int)
    case afterCompletionDays(Int)

    public var title: String {
        switch self {
        case .daily: return "Every Day"
        case .weekdays(let days):
            if days == Set(1...5) { return "Weekdays" }
            if days == Set([6, 7]) { return "Weekends" }
            let symbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return days.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
        case .everyDays(let n): return "Every \(max(1, n)) Days"
        case .monthly(let day): return "Monthly on Day \(max(1, day))"
        case .afterCompletionDays(let n): return "\(max(1, n)) Days After Completion"
        }
    }

    fileprivate var encoded: String {
        switch self {
        case .daily: return "daily"
        case .weekdays(let days): return "weekdays:" + days.sorted().map(String.init).joined(separator: ",")
        case .everyDays(let n): return "every:" + String(max(1, n))
        case .monthly(let day): return "monthly:" + String(min(31, max(1, day)))
        case .afterCompletionDays(let n): return "after:" + String(max(1, n))
        }
    }

    fileprivate static func decode(_ value: String) -> TodoRecurrenceRule? {
        if value == "daily" { return .daily }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "weekdays":
            let days = Set(parts[1].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            return days.isEmpty ? nil : .weekdays(days)
        case "every":
            guard let n = Int(parts[1]), n > 0 else { return nil }
            return .everyDays(n)
        case "monthly":
            guard let day = Int(parts[1]), (1...31).contains(day) else { return nil }
            return .monthly(day)
        case "after":
            guard let n = Int(parts[1]), n > 0 else { return nil }
            return .afterCompletionDays(n)
        default:
            return nil
        }
    }
}

public struct TodoRecurrence: Equatable, Sendable {
    public let seriesID: UUID
    public let rule: TodoRecurrenceRule
    public let scheduledDate: String

    public init(seriesID: UUID, rule: TodoRecurrenceRule, scheduledDate: String) {
        self.seriesID = seriesID
        self.rule = rule
        self.scheduledDate = scheduledDate
    }

    fileprivate var metadataLine: String {
        "<!-- drawer:repeat v=1 series=\(seriesID.uuidString.lowercased()) rule=\(rule.encoded) scheduled=\(scheduledDate) -->"
    }

    fileprivate static func parse(_ logicalLine: String) -> TodoRecurrence? {
        let trimmed = logicalLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!-- drawer:repeat "), trimmed.hasSuffix("-->") else { return nil }
        let body = trimmed
            .dropFirst("<!-- drawer:repeat ".count)
            .dropLast(3)
            .trimmingCharacters(in: .whitespaces)
        var fields: [String: String] = [:]
        for token in body.split(separator: " ") {
            let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        guard fields["v"] == "1",
              let idText = fields["series"], let id = UUID(uuidString: idText),
              let ruleText = fields["rule"], let rule = TodoRecurrenceRule.decode(ruleText),
              let scheduled = fields["scheduled"], DayMath.date(scheduled) != nil
        else { return nil }
        return TodoRecurrence(seriesID: id, rule: rule, scheduledDate: scheduled)
    }
}

/// Pure recurring-task transformations. All methods return transformed bytes;
/// callers remain responsible for the same compare/rebase/coordinated-write
/// transaction used by ordinary Drawer mutations.
public enum TodoRecurrenceWriteback {
    private struct Line {
        let start: String.Index
        let contentEnd: String.Index
        let end: String.Index
        let content: String
    }

    private struct Block {
        let taskIndex: Int
        let endIndex: Int
        let section: String
        let subsection: String?
        let occurrence: Int
        let rawLine: String
        let isDone: Bool
        let recurrence: TodoRecurrence?
        let recurrenceLineIndex: Int?
        let seriesResolutionLineIndex: Int?
    }

    public static func recurrence(for item: TodoItem, in data: Data) throws -> TodoRecurrence? {
        guard let text = String(data: data, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }
        let lines = scanLines(text)
        guard let block = locate(item: item, lines: lines) else { throw TodoRecurrenceError.taskNotFound }
        return block.recurrence
    }

    public static func setRecurrence(
        for item: TodoItem,
        rule: TodoRecurrenceRule?,
        today: String,
        in data: Data
    ) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }
        let lines = scanLines(text)
        guard let block = locate(item: item, lines: lines) else { throw TodoRecurrenceError.taskNotFound }

        if let existingIndex = block.recurrenceLineIndex {
            guard let rule else {
                return Data(removingLine(at: existingIndex, from: text, lines: lines).utf8)
            }
            let current = block.recurrence ?? TodoRecurrence(seriesID: UUID(), rule: rule, scheduledDate: item.sectionDate)
            let scheduled = DayMath.date(item.sectionDate) == nil ? today : item.sectionDate
            let replacement = indentation(of: lines[existingIndex].content) + TodoRecurrence(
                seriesID: current.seriesID,
                rule: rule,
                scheduledDate: scheduled
            ).metadataLine
            return Data(replacingContent(at: existingIndex, with: replacement, in: text, lines: lines).utf8)
        }

        guard let rule else { return data }
        let scheduled = DayMath.date(item.sectionDate) == nil ? today : item.sectionDate
        let recurrence = TodoRecurrence(seriesID: UUID(), rule: rule, scheduledDate: scheduled)
        let newline = lineEnding(in: text)
        let insertion = "    " + recurrence.metadataLine + newline
        let offset = lines[block.endIndex - 1].end
        var out = text
        out.insert(contentsOf: insertion, at: offset)
        return Data(out.utf8)
    }

    public static func completeAndAdvance(
        item: TodoItem,
        today: String,
        in data: Data
    ) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }
        let lines = scanLines(text)
        guard let block = locate(item: item, lines: lines) else { throw TodoRecurrenceError.taskNotFound }
        guard let recurrence = block.recurrence else { throw TodoRecurrenceError.noRecurrence }
        guard !block.isDone else { return data }
        try ensureSingleActiveSeries(recurrence.seriesID, excluding: block.taskIndex, lines: lines)

        let toggled = try TodoWriteback.toggle(
            line: item.rawLine,
            sectionDate: item.sectionDate,
            occurrence: item.occurrence,
            in: data
        )
        guard let toggledText = String(data: toggled, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }

        let nextDate = DayMath.nextDate(for: recurrence.rule, scheduled: recurrence.scheduledDate, resolvedOn: today)
        let successor = successorBlock(from: block, recurrence: recurrence, nextDate: nextDate, lines: lines, lineEnding: lineEnding(in: text))
        let output = insert(blockText: successor, intoSection: nextDate, subsection: block.subsection, in: toggledText)
        return Data(output.utf8)
    }

    public static func skipAndAdvance(
        item: TodoItem,
        today: String,
        in data: Data
    ) throws -> Data {
        let advanced = try completeAndAdvance(item: item, today: today, in: data)
        guard var text = String(data: advanced, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }
        let lines = scanLines(text)
        guard let completed = locateCompletedOriginal(item: item, lines: lines) else { return advanced }
        let newline = lineEnding(in: text)
        let insertion = "    <!-- drawer:resolution skipped -->" + newline
        let offset = lines[completed.endIndex - 1].end
        text.insert(contentsOf: insertion, at: offset)
        return Data(text.utf8)
    }

    /// Repairs externally-completed recurring occurrences (for example, when
    /// Obsidian checks a box) by generating the next occurrence exactly once.
    /// Repeated reconciliation is idempotent because an active instance with
    /// the same series ID suppresses generation.
    public static func reconcile(in data: Data, today: String) throws -> Data {
        guard let original = String(data: data, encoding: .utf8) else { throw TodoRecurrenceError.invalidUTF8 }
        var text = original
        var madeProgress = true
        var passes = 0

        while madeProgress, passes < 64 {
            passes += 1
            madeProgress = false
            let lines = scanLines(text)
            let blocks = scanBlocks(lines)
            let bySeries = Dictionary(grouping: blocks.compactMap { block -> (UUID, Block)? in
                guard let recurrence = block.recurrence else { return nil }
                return (recurrence.seriesID, block)
            }, by: { $0.0 })

            for (_, pairs) in bySeries {
                let seriesBlocks = pairs.map(\.1)
                let active = seriesBlocks.filter { !$0.isDone }
                if active.count > 1 { continue }
                if active.count == 1 { continue }
                guard let latest = seriesBlocks
                    .filter({ $0.isDone })
                    .max(by: { ($0.recurrence?.scheduledDate ?? "") < ($1.recurrence?.scheduledDate ?? "") }),
                      let recurrence = latest.recurrence
                else { continue }

                let nextDate = DayMath.nextDate(for: recurrence.rule, scheduled: recurrence.scheduledDate, resolvedOn: today)
                let successor = successorBlock(from: latest, recurrence: recurrence, nextDate: nextDate, lines: lines, lineEnding: lineEnding(in: text))
                text = insert(blockText: successor, intoSection: nextDate, subsection: latest.subsection, in: text)
                madeProgress = true
                break
            }
        }
        return Data(text.utf8)
    }

    // MARK: - Scanning

    private static func scanLines(_ text: String) -> [Line] {
        var result: [Line] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let newline = text[cursor...].firstIndex(of: "\n")
            let rawEnd = newline ?? text.endIndex
            var contentEnd = rawEnd
            if contentEnd > cursor {
                let previous = text.index(before: contentEnd)
                if text[previous] == "\r" { contentEnd = previous }
            }
            let end = newline.map { text.index(after: $0) } ?? text.endIndex
            result.append(Line(start: cursor, contentEnd: contentEnd, end: end, content: String(text[cursor..<contentEnd])))
            cursor = end
        }
        if text.isEmpty { return [] }
        return result
    }

    private static func scanBlocks(_ lines: [Line]) -> [Block] {
        var result: [Block] = []
        var section: String?
        var subsection: String?
        var occurrences: [String: Int] = [:]
        var fence: Character?
        var i = 0

        while i < lines.count {
            let line = lines[i].content
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker(trimmed) {
                if fence == nil { fence = marker }
                else if fence == marker { fence = nil }
                i += 1
                continue
            }
            if fence != nil { i += 1; continue }

            if line.hasPrefix("## "), !line.hasPrefix("### ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                subsection = nil
                occurrences.removeAll(keepingCapacity: true)
                i += 1
                continue
            }
            if line.hasPrefix("### ") {
                subsection = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                i += 1
                continue
            }
            guard let section, checkboxState(line) != nil else { i += 1; continue }

            let occurrence = occurrences[line, default: 0]
            occurrences[line] = occurrence + 1
            var end = i + 1
            var recurrence: TodoRecurrence?
            var recurrenceLine: Int?
            var resolutionLine: Int?
            while end < lines.count {
                let child = lines[end].content
                if child.isEmpty { break }
                guard isIndented(child) else { break }
                let trimmedChild = child.trimmingCharacters(in: .whitespaces)
                if let parsed = TodoRecurrence.parse(trimmedChild) {
                    recurrence = parsed
                    recurrenceLine = end
                }
                if trimmedChild == "<!-- drawer:resolution skipped -->" { resolutionLine = end }
                end += 1
            }
            result.append(Block(
                taskIndex: i,
                endIndex: end,
                section: section,
                subsection: subsection,
                occurrence: occurrence,
                rawLine: line,
                isDone: checkboxState(line) == "x",
                recurrence: recurrence,
                recurrenceLineIndex: recurrenceLine,
                seriesResolutionLineIndex: resolutionLine
            ))
            i = max(i + 1, end)
        }
        return result
    }

    private static func locate(item: TodoItem, lines: [Line]) -> Block? {
        scanBlocks(lines).first {
            $0.section == item.sectionDate && $0.rawLine == item.rawLine && $0.occurrence == item.occurrence
        }
    }

    private static func locateCompletedOriginal(item: TodoItem, lines: [Line]) -> Block? {
        let titleTail = taskTail(item.rawLine)
        return scanBlocks(lines).first {
            $0.section == item.sectionDate && $0.isDone && taskTail($0.rawLine) == titleTail
        }
    }

    private static func ensureSingleActiveSeries(_ id: UUID, excluding taskIndex: Int, lines: [Line]) throws {
        let otherActive = scanBlocks(lines).contains {
            $0.taskIndex != taskIndex && !$0.isDone && $0.recurrence?.seriesID == id
        }
        if otherActive { throw TodoRecurrenceError.duplicateActiveSeries }
    }

    // MARK: - Text transforms

    private static func successorBlock(
        from block: Block,
        recurrence: TodoRecurrence,
        nextDate: String,
        lines: [Line],
        lineEnding: String
    ) -> String {
        var parts: [String] = []
        parts.append(openCheckbox(block.rawLine))
        if block.endIndex > block.taskIndex + 1 {
            for index in (block.taskIndex + 1)..<block.endIndex {
                let content = lines[index].content
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                if TodoRecurrence.parse(trimmed) != nil || trimmed == "<!-- drawer:resolution skipped -->" { continue }
                parts.append(content)
            }
        }
        parts.append("    " + TodoRecurrence(seriesID: recurrence.seriesID, rule: recurrence.rule, scheduledDate: nextDate).metadataLine)
        return parts.joined(separator: lineEnding) + lineEnding
    }

    private static func insert(blockText: String, intoSection target: String, subsection: String?, in text: String) -> String {
        let newline = lineEnding(in: text)
        var lines = scanLines(text)

        if let sectionIndex = lines.firstIndex(where: { $0.content == "## " + target }) {
            var sectionEnd = lines.count
            for i in (sectionIndex + 1)..<lines.count where lines[i].content.hasPrefix("## ") && !lines[i].content.hasPrefix("### ") {
                sectionEnd = i
                break
            }

            if let subsection, !subsection.isEmpty {
                var matchingSubsection: Int?
                if sectionIndex + 1 < sectionEnd {
                    for i in (sectionIndex + 1)..<sectionEnd where lines[i].content == "### " + subsection {
                        matchingSubsection = i
                        break
                    }
                }
                if let matchingSubsection {
                    var insertionLine = sectionEnd
                    if matchingSubsection + 1 < sectionEnd {
                        for i in (matchingSubsection + 1)..<sectionEnd where lines[i].content.hasPrefix("### ") {
                            insertionLine = i
                            break
                        }
                    }
                    let index = insertionLine < lines.count ? lines[insertionLine].start : text.endIndex
                    var out = text
                    let prefix = needsLeadingNewline(before: index, in: text) ? newline : ""
                    out.insert(contentsOf: prefix + blockText, at: index)
                    return out
                }

                let index = sectionEnd < lines.count ? lines[sectionEnd].start : text.endIndex
                var out = text
                let prefix = needsLeadingNewline(before: index, in: text) ? newline : ""
                out.insert(contentsOf: prefix + "### " + subsection + newline + newline + blockText, at: index)
                return out
            }

            var insertionLine = sectionEnd
            if sectionIndex + 1 < sectionEnd {
                for i in (sectionIndex + 1)..<sectionEnd where lines[i].content.hasPrefix("### ") {
                    insertionLine = i
                    break
                }
            }
            let index = insertionLine < lines.count ? lines[insertionLine].start : text.endIndex
            var out = text
            let prefix = needsLeadingNewline(before: index, in: text) ? newline : ""
            out.insert(contentsOf: prefix + blockText, at: index)
            return out
        }

        let prefix: String
        if text.isEmpty { prefix = "" }
        else if text.hasSuffix("\n\n") || text.hasSuffix("\r\n\r\n") { prefix = "" }
        else if text.hasSuffix("\n") { prefix = newline }
        else { prefix = newline + newline }
        let group = subsection.map { "### " + $0 + newline + newline } ?? ""
        return text + prefix + "## " + target + newline + newline + group + blockText
    }

    private static func replacingContent(at index: Int, with replacement: String, in text: String, lines: [Line]) -> String {
        var out = text
        out.replaceSubrange(lines[index].start..<lines[index].contentEnd, with: replacement)
        return out
    }

    private static func removingLine(at index: Int, from text: String, lines: [Line]) -> String {
        var out = text
        out.removeSubrange(lines[index].start..<lines[index].end)
        return out
    }

    private static func lineEnding(in text: String) -> String { text.contains("\r\n") ? "\r\n" : "\n" }

    private static func needsLeadingNewline(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return false }
        let prefix = text[..<index]
        return !(prefix.hasSuffix("\n\n") || prefix.hasSuffix("\r\n\r\n"))
    }

    private static func indentation(of line: String) -> String { String(line.prefix { $0 == " " || $0 == "\t" }) }
    private static func isIndented(_ line: String) -> Bool { line.hasPrefix(" ") || line.hasPrefix("\t") }

    private static func checkboxState(_ line: String) -> Character? {
        guard line.count >= 6 else { return nil }
        let prefix = String(line.prefix(6)).lowercased()
        if prefix == "- [ ] " { return " " }
        if prefix == "- [/] " { return "/" }
        if prefix == "- [x] " { return "x" }
        return nil
    }

    private static func taskTail(_ line: String) -> String { line.count >= 6 ? String(line.dropFirst(6)) : line }

    private static func openCheckbox(_ line: String) -> String {
        guard checkboxState(line) != nil else { return line }
        return "- [ ] " + taskTail(line)
    }

    private static func fenceMarker(_ trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }
}

private enum DayMath {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func nextDate(for rule: TodoRecurrenceRule, scheduled: String, resolvedOn today: String) -> String {
        let scheduledDate = date(scheduled) ?? date(today) ?? Date()
        let todayDate = date(today) ?? Date()
        let base = max(scheduledDate, todayDate)
        let cal = calendar

        switch rule {
        case .daily:
            return key(cal.date(byAdding: .day, value: 1, to: base)!)

        case .weekdays(let allowed):
            var candidate = cal.date(byAdding: .day, value: 1, to: base)!
            for _ in 0..<8 {
                let appleWeekday = cal.component(.weekday, from: candidate) // Sun=1
                let iso = appleWeekday == 1 ? 7 : appleWeekday - 1
                if allowed.contains(iso) { return key(candidate) }
                candidate = cal.date(byAdding: .day, value: 1, to: candidate)!
            }
            return key(candidate)

        case .everyDays(let interval):
            let n = max(1, interval)
            var candidate = scheduledDate
            repeat { candidate = cal.date(byAdding: .day, value: n, to: candidate)! } while candidate <= todayDate
            return key(candidate)

        case .monthly(let requestedDay):
            var cursor = base
            for _ in 0..<14 {
                cursor = cal.date(byAdding: .month, value: 1, to: cursor)!
                let ym = cal.dateComponents([.year, .month], from: cursor)
                guard let monthAnchor = cal.date(from: DateComponents(year: ym.year, month: ym.month, day: 1, hour: 12)),
                      let range = cal.range(of: .day, in: .month, for: monthAnchor)
                else { continue }
                let day = min(max(1, requestedDay), range.count)
                if let candidate = cal.date(from: DateComponents(year: ym.year, month: ym.month, day: day, hour: 12)), candidate > base {
                    return key(candidate)
                }
            }
            return key(cal.date(byAdding: .month, value: 1, to: base)!)

        case .afterCompletionDays(let interval):
            return key(cal.date(byAdding: .day, value: max(1, interval), to: todayDate)!)
        }
    }
}
