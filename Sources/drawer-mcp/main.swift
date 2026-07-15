import DrawerCore
import Foundation
import MCP

// drawer-mcp: the Model Context Protocol server for Drawer. A thin stdio adapter
// over DrawerCore.DrawerToolService — it owns the MCP tool schemas, argument
// decoding, result/error formatting, and the server lifecycle, and nothing else.
// All drawer logic (parsing, byte-safe writeback, plan validation) lives in
// DrawerCore, never reimplemented here. Pure Foundation, no AppKit.

// MARK: - stderr logging (stdout is reserved for protocol traffic)

func logError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - File + path wiring

// First hit wins: --file arg, DRAWER_FILE env, the app's saved default (read
// from its preferences domain), then the shared DrawerFilePath.default.
let drawerPath = DrawerFilePath.resolve(
    arguments: CommandLine.arguments,
    environment: ProcessInfo.processInfo.environment,
    storedDefault: DrawerFilePath.storedAppDefault(bundleID: "com.bbrizly.drawer")
)
let drawerURL = URL(fileURLWithPath: drawerPath)

let appSupport = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ?? FileManager.default.homeDirectoryForCurrentUser
let workLogURL = appSupport.appendingPathComponent("Drawer/work-sessions.jsonl")

let todayProvider: @Sendable () -> String = {
    let f = DateFormatter()
    // POSIX locale: a Buddhist/Japanese system calendar would otherwise
    // render year 2569 and file tasks under a day no heading matches.
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = Calendar.current.timeZone
    return f.string(from: Date())
}

let service = DrawerToolService(
    read: { try Data(contentsOf: drawerURL) },
    write: { data in
        try FileManager.default.createDirectory(
            at: drawerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: drawerURL, options: .atomic)
    },
    workLog: WorkSessionLog(fileURL: workLogURL),
    today: todayProvider
)

// Serializes read-modify-write across concurrent tool calls in this process, so
// two mutations can't interleave and clobber each other. Cross-process safety
// (Obsidian, the app) rests on DrawerCore's line-targeted writeback + atomic
// writes, not on this actor.
actor DrawerGateway {
    let service: DrawerToolService
    init(_ service: DrawerToolService) { self.service = service }

    func listTasks(section: DrawerToolService.TaskSection, includeDone: Bool) throws -> [TaskDTO] {
        try service.listTasks(section: section, includeDone: includeDone)
    }
    func addTask(title: String, section: String?, date: String?, note: String?, minutes: Int?) throws -> TaskDTO {
        try service.addTask(title: title, section: section, date: date, note: note, minutes: minutes)
    }
    func toggleTask(id: String) throws -> ToggleResult {
        try retryOnMovedLine { try service.toggleTask(id: id) }
    }
    func getWorkSummary(day: String?) -> WorkSummaryDTO {
        service.getWorkSummary(day: day)
    }
    func writeDayPlan(date: String, entries: [PlanEntry], replace: Bool) throws -> WritePlanResult {
        try service.writeDayPlan(date: date, entries: entries, replace: replace)
    }

    /// Per the concurrency model: if a target line moved under us (an external
    /// edit landed between our read and write), re-read and re-apply once. Each
    /// service call reads fresh, so a second attempt is a genuine retry.
    private func retryOnMovedLine<T>(_ op: () throws -> T) throws -> T {
        do { return try op() }
        catch WritebackError.lineNotFound { return try op() }
    }
}
let gateway = DrawerGateway(service)

// MARK: - Result / error encoding

let jsonEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    e.outputFormatting = [.sortedKeys]
    return e
}()

func ok<T: Encodable>(_ value: T) -> CallTool.Result {
    let json = (try? jsonEncoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    return CallTool.Result(content: [.text(text: json)], isError: false)
}

func fail(_ message: String) -> CallTool.Result {
    CallTool.Result(content: [.text(text: message)], isError: true)
}

/// Maps a thrown error to a one-line client remedy.
func remedy(for error: Error) -> String {
    switch error {
    case let e as ToolArgumentError:
        return e.message
    case DrawerToolError.taskNotFound:
        return "No task with that id. Call list_tasks again for fresh ids."
    case DrawerToolError.badEncoding, WritebackError.badEncoding, PlanWriterError.badEncoding:
        return "The drawer file is not valid UTF-8; refusing to read or write it."
    case WritebackError.lineNotFound:
        return "The target line moved. Call list_tasks again for fresh ids."
    case PlanWriterError.emptyPlan:
        return "A plan needs at least one entry."
    case let PlanWriterError.tooManyEntries(n):
        return "A plan allows at most \(PlanWriter.maxEntries) entries; got \(n)."
    case PlanWriterError.tooManyNewTasks:
        return "A plan may add at most one brand-new task."
    case let PlanWriterError.unresolvedTaskID(id):
        return "task_id \(id) does not resolve. Call list_tasks for fresh ids."
    case let PlanWriterError.taskIDTitleMismatch(id):
        return "task_id \(id) does not match its title. Use no task_id for a new task."
    case let PlanWriterError.invalidDate(d):
        return "date '\(d)' is not a valid YYYY-MM-DD."
    case let PlanWriterError.invalidEntry(title):
        return "Entry '\(title)' has an invalid title, note, or minutes "
            + "(no newlines or fences, minutes 1-480, title <= 500 chars, note <= 4096)."
    default:
        // The full error already went to stderr; don't leak NSError internals
        // (absolute paths, userInfo) to the client.
        return "Unexpected error; see the server log."
    }
}

// MARK: - Argument helpers

func string(_ args: [String: Value]?, _ key: String) -> String? { args?[key]?.stringValue }
func int(_ args: [String: Value]?, _ key: String) -> Int? { args?[key]?.intValue }
func bool(_ args: [String: Value]?, _ key: String) -> Bool? { args?[key]?.boolValue }

struct ToolArgumentError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Strict decode: a malformed entry fails the whole call rather than being
/// silently dropped into a partial plan mutation.
func planEntries(_ args: [String: Value]?) throws -> [PlanEntry] {
    guard let raw = args?["entries"] else {
        throw ToolArgumentError("write_day_plan requires an entries array.")
    }
    guard let array = raw.arrayValue else {
        throw ToolArgumentError("entries must be an array.")
    }
    return try array.enumerated().map { index, value in
        guard let object = value.objectValue else {
            throw ToolArgumentError("entry \(index) must be an object.")
        }
        guard let title = object["title"]?.stringValue else {
            throw ToolArgumentError("entry \(index) needs a string title.")
        }
        return PlanEntry(
            title: title,
            minutes: object["minutes"]?.intValue,
            note: object["note"]?.stringValue,
            taskID: object["task_id"]?.stringValue ?? object["taskID"]?.stringValue
        )
    }
}

// MARK: - Tool catalog

let tools: [Tool] = [
    Tool(
        name: "list_tasks",
        description: "List drawer tasks. section is one of today, carried, upcoming, backlog, archive, all (default all).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "section": .object(["type": .string("string")]),
                "include_done": .object(["type": .string("boolean")]),
            ]),
        ])
    ),
    Tool(
        name: "add_task",
        description: "Add a task. Defaults to today. Pass date (YYYY-MM-DD) for a dated section, or section=backlog/archive. minutes writes a (Nm) hint; note writes indented lines.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "section": .object(["type": .string("string")]),
                "date": .object(["type": .string("string")]),
                "note": .object(["type": .string("string")]),
                "minutes": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("title")]),
        ])
    ),
    Tool(
        name: "toggle_task",
        description: "Flip a task's checkbox by its id (from list_tasks).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["id": .object(["type": .string("string")])]),
            "required": .array([.string("id")]),
        ])
    ),
    Tool(
        name: "get_work_summary",
        description: "Logged work for a day (default today): per-task seconds with source (auto/manual/mixed), total, and longest session.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object(["day": .object(["type": .string("string")])]),
        ])
    ),
    Tool(
        name: "write_day_plan",
        description: "Write a day's plan. entries are {title, minutes?, note?, task_id?}. Appends/merges by default (keeps checked tasks); replace=true replaces only unchecked tasks.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "date": .object(["type": .string("string")]),
                "entries": .object(["type": .string("array")]),
                "replace": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("date"), .string("entries")]),
        ])
    ),
]

// MARK: - Server

let server = Server(
    name: "drawer",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: tools)
}

await server.withMethodHandler(CallTool.self) { params in
    let args = params.arguments
    do {
        switch params.name {
        case "list_tasks":
            var section = DrawerToolService.TaskSection.all
            if let raw = string(args, "section") {
                guard let parsed = DrawerToolService.TaskSection(rawValue: raw) else {
                    return fail("Unknown section '\(raw)'. Use today, carried, upcoming, backlog, archive, or all.")
                }
                section = parsed
            }
            let includeDone = bool(args, "include_done") ?? true
            return ok(try await gateway.listTasks(section: section, includeDone: includeDone))

        case "add_task":
            guard let title = string(args, "title") else { return fail("add_task requires a title.") }
            if let raw = string(args, "section"), !["today", "backlog", "archive"].contains(raw) {
                return fail("add_task section must be today, backlog, or archive; pass date for a specific day.")
            }
            return ok(try await gateway.addTask(
                title: title, section: string(args, "section"), date: string(args, "date"),
                note: string(args, "note"), minutes: int(args, "minutes")))

        case "toggle_task":
            guard let id = string(args, "id") else { return fail("toggle_task requires an id.") }
            return ok(try await gateway.toggleTask(id: id))

        case "get_work_summary":
            return ok(await gateway.getWorkSummary(day: string(args, "day")))

        case "write_day_plan":
            guard let date = string(args, "date") else { return fail("write_day_plan requires a date.") }
            return ok(try await gateway.writeDayPlan(
                date: date, entries: try planEntries(args), replace: bool(args, "replace") ?? false))

        default:
            return fail("Unknown tool: \(params.name)")
        }
    } catch {
        logError("[drawer-mcp] \(params.name) failed: \(error)")
        return fail(remedy(for: error))
    }
}

logError("[drawer-mcp] serving \(drawerURL.path)")
let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
