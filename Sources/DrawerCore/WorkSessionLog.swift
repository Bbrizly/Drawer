import Foundation

/// Append-only JSONL store of work sessions. One JSON object per line, appended
/// in O(1) with a file handle so the log never gets rewritten whole. Every disk
/// operation is an injectable closure, so tests run in memory and never touch
/// the filesystem.
public struct WorkSessionLog: Sendable {
    public let fileURL: URL
    private let read: @Sendable (URL) throws -> String
    private let appendLine: @Sendable (String, URL) throws -> Void
    private let overwrite: @Sendable (String, URL) throws -> Void

    public init(
        fileURL: URL,
        read: @escaping @Sendable (URL) throws -> String = {
            try String(contentsOf: $0, encoding: .utf8)
        },
        appendLine: @escaping @Sendable (String, URL) throws -> Void = { line, url in
            let fm = FileManager.default
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        },
        overwrite: @escaping @Sendable (String, URL) throws -> Void = { value, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try value.write(to: url, atomically: true, encoding: .utf8)
        }
    ) {
        self.fileURL = fileURL
        self.read = read
        self.appendLine = appendLine
        self.overwrite = overwrite
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = calendar.timeZone
        return f
    }

    /// Every session in the log. A corrupt line is skipped, never fatal.
    public func all() -> [WorkSession] {
        guard let text = try? read(fileURL) else { return [] }
        let dec = Self.decoder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(WorkSession.self, from: Data($0.utf8))
        }
    }

    /// Appends one session. Sub-second spans are dropped so a double-tap never
    /// writes noise.
    public func append(_ session: WorkSession) throws {
        guard session.seconds >= 1 else { return }
        let line = String(decoding: try Self.encoder().encode(session), as: UTF8.self) + "\n"
        try appendLine(line, fileURL)
    }

    /// Rewrites the whole log. Backs edit and delete of a session by id.
    public func replaceAll(_ sessions: [WorkSession]) throws {
        let enc = Self.encoder()
        let body = try sessions
            .map { String(decoding: try enc.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
        try overwrite(body.isEmpty ? "" : body + "\n", fileURL)
    }

    /// Total logged seconds for one task title on one day.
    public func total(
        forTitle title: String, on day: String, calendar: Calendar = .current
    ) -> TimeInterval {
        let f = Self.dayFormatter(calendar)   // one formatter, not one per row
        return all()
            .filter { $0.taskTitle == title && f.string(from: $0.start) == day }
            .reduce(0) { $0 + $1.seconds }
    }

    /// Anchors a "yyyy-MM-dd" string to noon that day, clear of DST and timezone
    /// edges, so a synthetic edited session groups under the right day.
    private static func dayAnchor(_ day: String, _ calendar: Calendar) -> Date? {
        guard let midnight = dayFormatter(calendar).date(from: day) else { return nil }
        return calendar.date(byAdding: .hour, value: 12, to: midnight)
    }

    /// Edits a task's logged total for a day: drops that task's sessions on that
    /// day and replaces them with a single session of `seconds`. Pass 0 to remove
    /// the task. Other tasks and other days are untouched.
    public func setTotal(
        forTitle title: String, on day: String, seconds: TimeInterval, calendar: Calendar = .current
    ) throws {
        let f = Self.dayFormatter(calendar)
        var result = all().filter { !($0.taskTitle == title && f.string(from: $0.start) == day) }
        if seconds >= 1, let start = Self.dayAnchor(day, calendar) {
            result.append(WorkSession(
                taskID: title, taskTitle: title, start: start, end: start.addingTimeInterval(seconds)))
        }
        try replaceAll(result)
    }

    /// One summary per day that has logged time, most recent day first.
    public func allSummaries(calendar: Calendar = .current) -> [WorkSummary] {
        let f = Self.dayFormatter(calendar)
        let days = Set(all().filter(\.isAttributable).map { f.string(from: $0.start) })
        return days.sorted(by: >).map { summary(for: $0, calendar: calendar) }
    }

    /// Per-task roll-up for one day, longest first. Approved-but-unattributed
    /// time is real logged time but not task work, so it is excluded here: it
    /// never shows as a blank row or inflates a per-task total.
    public func summary(for day: String, calendar: Calendar = .current) -> WorkSummary {
        let f = Self.dayFormatter(calendar)
        let sameDay = all().filter { $0.isAttributable && f.string(from: $0.start) == day }
        var byTitle: [String: TimeInterval] = [:]
        for s in sameDay { byTitle[s.taskTitle, default: 0] += s.seconds }
        let rows = byTitle
            .map { WorkSummary.Row(taskTitle: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
        return WorkSummary(
            day: day,
            rows: rows,
            total: rows.reduce(0) { $0 + $1.seconds },
            longest: sameDay.max { $0.seconds < $1.seconds }
        )
    }
}
