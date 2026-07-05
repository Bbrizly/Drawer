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
        let entry = PlanEntry(title: title, minutes: minutes, note: note)
        // Same content guard on every path (the backlog insert doesn't go
        // through PlanWriter, so validate here too — no newline/checkbox
        // injection reaches the shared file).
        try PlanWriter.checkEntryContent(entry)

        let toDate = date
        let toNamed = (section == TodoParser.backlogKey || section == TodoParser.archiveKey) ? section : nil
        let key = toDate ?? toNamed ?? today()

        let out = try mutate { data in
            if let toDate {
                return try PlanWriter.write(date: toDate, entries: [entry], replace: false, in: data)
            } else if let toNamed {
                return try insertIntoNamedSection(
                    toNamed, title: title, note: note, minutes: minutes, in: data)
            } else {
                return try PlanWriter.write(date: today(), entries: [entry], replace: false, in: data)
            }
        }

        let target = TitleSimilarity.normalize(title)
        return buildDTOs(String(decoding: out, as: UTF8.self))
            .last { $0.date == key && TitleSimilarity.normalize($0.title) == target }
            ?? TaskDTO(
                id: "\(key)|0|\(entry.taskID ?? "")", title: title, done: false, inProgress: false,
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

    /// Toggles by `TodoItem.id` (`sectionDate|occurrence|rawLine`). A stale id
    /// whose exact line no longer exists fails safe (taskNotFound, or
    /// lineNotFound from the writeback). Known edge of the shared id scheme: two
    /// *identical* task lines in one section are told apart only by occurrence,
    /// so if an external edit inserts/removes an identical line, a stale id can
    /// land on the sibling. This is the same id the in-app UI uses; unique task
    /// text avoids it, and duplicate identical tasks are already ambiguous.
    public func toggleTask(id: String) throws -> ToggleResult {
        var captured: ToggleResult?
        _ = try mutate { data in
            guard let text = String(data: data, encoding: .utf8) else {
                throw DrawerToolError.badEncoding
            }
            guard let item = TodoParser.parse(text).flatMap(\.items).first(where: { $0.id == id }) else {
                throw DrawerToolError.taskNotFound(id)
            }
            captured = ToggleResult(title: item.title, done: !item.isDone)
            return try TodoWriteback.toggle(
                line: item.rawLine, sectionDate: item.sectionDate, occurrence: item.occurrence, in: data)
        }
        return captured!  // mutate ran the transform at least once, or threw
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
        let out = try mutate { data in
            try PlanWriter.write(date: date, entries: entries, replace: replace, in: data)
        }
        let tasks = buildDTOs(String(decoding: out, as: UTF8.self)).filter { $0.date == date }
        return WritePlanResult(date: date, tasks: tasks)
    }

    // MARK: helpers

    /// Current bytes and their UTF-8 text. A missing file reads as empty; a
    /// present-but-non-UTF-8 file errors so no tool ever parses or overwrites it.
    private func load() throws -> (Data, String) {
        let data = try readOrEmpty()
        guard let text = String(data: data, encoding: .utf8) else {
            throw DrawerToolError.badEncoding
        }
        return (data, text)
    }

    /// Reads the file, mapping only a genuine "no such file" to empty. A
    /// permission or I/O failure must surface, never masquerade as an empty
    /// drawer (which would silently drop the user's tasks on the next write).
    private func readOrEmpty() throws -> Data {
        do { return try read() }
        catch {
            if isFileNotFound(error) { return Data() }
            throw error
        }
    }

    private func isFileNotFound(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoSuchFileError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) { return true }
        return false
    }

    /// Content-based compare-and-swap for whole-file writes: read, compute the
    /// new bytes, then re-read just before writing. If the file changed under us
    /// (a concurrent Obsidian/app save), recompute once against the fresh bytes
    /// so that edit isn't clobbered. Content comparison, not an mtime guard, per
    /// the spec's write-concurrency model. Returns the bytes written.
    private func mutate(_ transform: (Data) throws -> Data) throws -> Data {
        var data = try readOrEmpty()
        var out = try transform(data)
        let fresh = try readOrEmpty()
        if fresh != data {
            data = fresh
            out = try transform(data)
        }
        try write(out)
        return out
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
