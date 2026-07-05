import Foundation

/// The five drawer operations an MCP client can perform, as pure logic with
/// injectable file access so every tool is testable against an in-memory file.
/// The `drawer-mcp` executable is a thin adapter over this: it owns the MCP
/// schemas, argument decoding, and stdio lifecycle, and calls straight through
/// here. Every mutating call reads fresh bytes, edits through DrawerCore's
/// byte-safe writeback, and writes atomically — never caching a parse across
/// calls, so a concurrent Obsidian edit can't be clobbered by stale state.
public struct DrawerToolService: Sendable {
    private let read: @Sendable () throws -> Data
    private let write: @Sendable (Data) throws -> Void
    private let workLog: WorkSessionLog
    private let today: @Sendable () -> String

    public init(
        read: @escaping @Sendable () throws -> Data,
        write: @escaping @Sendable (Data) throws -> Void,
        workLog: WorkSessionLog,
        today: @escaping @Sendable () -> String
    ) {
        self.read = read
        self.write = write
        self.workLog = workLog
        self.today = today
    }

    public enum TaskSection: String, Sendable {
        case today, carried, upcoming, backlog, archive, all
    }

    // MARK: list_tasks

    public func listTasks(section: TaskSection, includeDone: Bool) throws -> [TaskDTO] {
        let (_, text) = try load()
        var dtos = buildDTOs(text)
        if section != .all { dtos = dtos.filter { $0.section == section.rawValue } }
        if !includeDone { dtos = dtos.filter { !$0.done } }
        return dtos
    }

    // MARK: add_task

    public func addTask(
        title: String, section: String?, date: String?, note: String?, minutes: Int?
    ) throws -> TaskDTO {
        let (data, _) = try load()
        let entry = PlanEntry(title: title, minutes: minutes, note: note)
        let key: String
        let out: Data
        if let date {
            out = try PlanWriter.write(date: date, entries: [entry], replace: false, in: data)
            key = date
        } else if let section, section == TodoParser.backlogKey || section == TodoParser.archiveKey {
            out = try insertIntoNamedSection(section, title: title, note: note, minutes: minutes, in: data)
            key = section
        } else {
            out = try PlanWriter.write(date: today(), entries: [entry], replace: false, in: data)
            key = today()
        }
        try write(out)

        let fresh = buildDTOs(String(decoding: out, as: UTF8.self))
        let target = TitleSimilarity.normalize(title)
        return fresh.last { $0.date == key && TitleSimilarity.normalize($0.title) == target }
            ?? TaskDTO(
                id: "", title: title, done: false, inProgress: false,
                minutes: minutes ?? 25, section: key, date: key, note: note
            )
    }

    /// Backlog/Archive aren't date sections, so PlanWriter (date-only) can't
    /// place them; use the byte-safe section insert + note writeback instead.
    private func insertIntoNamedSection(
        _ key: String, title: String, note: String?, minutes: Int?, in data: Data
    ) throws -> Data {
        var line = "- [ ] " + title
        if let minutes { line += " (\(minutes)m)" }
        let heading = key.prefix(1).uppercased() + key.dropFirst()
        var out = try TodoWriteback.insert(
            line: line, intoSectionKey: key, displayHeading: heading, in: data)
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let occurrence = TodoParser.parse(String(decoding: out, as: UTF8.self))
                .first { $0.date == key }?.items
                .filter { $0.rawLine == line }.count ?? 1
            out = try TodoWriteback.setNote(
                line: line, sectionDate: key, occurrence: max(0, occurrence - 1), note: note, in: out)
        }
        return out
    }

    // MARK: toggle_task

    public func toggleTask(id: String) throws -> ToggleResult {
        let (data, text) = try load()
        guard let item = TodoParser.parse(text).flatMap(\.items).first(where: { $0.id == id }) else {
            throw DrawerToolError.taskNotFound(id)
        }
        let out = try TodoWriteback.toggle(
            line: item.rawLine, sectionDate: item.sectionDate, occurrence: item.occurrence, in: data)
        try write(out)
        return ToggleResult(title: item.title, done: !item.isDone)
    }

    // MARK: get_work_summary

    public func getWorkSummary(day: String?) -> WorkSummaryDTO {
        let target = day ?? today()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        let sessions = workLog.all().filter { formatter.string(from: $0.start) == target }

        var secondsByTitle: [String: TimeInterval] = [:]
        var sourcesByTitle: [String: Set<String>] = [:]
        for s in sessions {
            secondsByTitle[s.taskTitle, default: 0] += s.seconds
            sourcesByTitle[s.taskTitle, default: []].insert(s.source ?? "manual")
        }
        let rows = secondsByTitle.map { title, seconds in
            let sources = sourcesByTitle[title] ?? []
            let source = sources == ["auto"] ? "auto" : (sources == ["manual"] ? "manual" : "mixed")
            return WorkSummaryDTO.Row(title: title, seconds: Int(seconds.rounded()), source: source)
        }.sorted { $0.seconds > $1.seconds }

        let longest = sessions.max { $0.seconds < $1.seconds }
        return WorkSummaryDTO(
            day: target,
            totalSeconds: rows.reduce(0) { $0 + $1.seconds },
            rows: rows,
            longestTitle: longest?.taskTitle,
            longestSeconds: longest.map { Int($0.seconds.rounded()) }
        )
    }

    // MARK: write_day_plan

    public func writeDayPlan(
        date: String, entries: [PlanEntry], replace: Bool
    ) throws -> WritePlanResult {
        let (data, _) = try load()
        let out = try PlanWriter.write(date: date, entries: entries, replace: replace, in: data)
        try write(out)
        let tasks = buildDTOs(String(decoding: out, as: UTF8.self)).filter { $0.date == date }
        return WritePlanResult(date: date, tasks: tasks)
    }

    // MARK: helpers

    /// Current bytes and their UTF-8 text. A missing file reads as empty; a
    /// present-but-non-UTF-8 file errors so no tool ever parses or overwrites it.
    private func load() throws -> (Data, String) {
        let data = (try? read()) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw DrawerToolError.badEncoding
        }
        return (data, text)
    }

    private func buildDTOs(_ text: String) -> [TaskDTO] {
        let display = TodoParser.display(sections: TodoParser.parse(text), today: today())
        var out: [TaskDTO] = []
        func add(_ items: [TodoItem], _ section: String) {
            out += items.map {
                TaskDTO(
                    id: $0.id, title: $0.title, done: $0.isDone, inProgress: $0.isInProgress,
                    minutes: $0.minutes, section: section, date: $0.sectionDate, note: $0.note
                )
            }
        }
        add(display.today, "today")
        add(display.carried, "carried")
        add(display.upcoming, "upcoming")
        add(display.backlog, "backlog")
        add(display.archive, "archive")
        return out
    }
}

public enum DrawerToolError: Error, Equatable {
    case badEncoding
    case taskNotFound(String)
}

public struct TaskDTO: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let done: Bool
    public let inProgress: Bool
    public let minutes: Int
    public let section: String
    public let date: String
    public let note: String?
}

public struct ToggleResult: Codable, Equatable, Sendable {
    public let title: String
    public let done: Bool
}

public struct WorkSummaryDTO: Codable, Equatable, Sendable {
    public struct Row: Codable, Equatable, Sendable {
        public let title: String
        public let seconds: Int
        public let source: String
    }
    public let day: String
    public let totalSeconds: Int
    public let rows: [Row]
    public let longestTitle: String?
    public let longestSeconds: Int?
}

public struct WritePlanResult: Codable, Equatable, Sendable {
    public let date: String
    public let tasks: [TaskDTO]
}
