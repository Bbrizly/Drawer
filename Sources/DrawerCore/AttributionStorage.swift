import Foundation

/// Drops a sample whose app and normalized title match the previous kept one,
/// so a titlebar flapping between "file" and "file - Edited" writes one line,
/// not hundreds.
public func coalesceSamples(_ samples: [ActivitySample]) -> [ActivitySample] {
    var out: [ActivitySample] = []
    for sample in samples {
        if let last = out.last,
           last.bundleID == sample.bundleID,
           last.normalizedTitle == sample.normalizedTitle {
            continue
        }
        out.append(sample)
    }
    return out
}

/// Append-only JSONL of raw activity samples, kept to a 7-day ring. Injectable
/// I/O like WorkSessionLog. Window titles can hold sensitive text, so this is
/// local-only and short-lived; it never reaches the work log.
public struct RawActivityStore: Sendable {
    public static let retention: TimeInterval = 7 * 86400

    public let fileURL: URL
    private let read: @Sendable (URL) throws -> String
    private let appendLine: @Sendable (String, URL) throws -> Void
    private let overwrite: @Sendable (String, URL) throws -> Void

    public init(
        fileURL: URL,
        read: @escaping @Sendable (URL) throws -> String = { try String(contentsOf: $0, encoding: .utf8) },
        appendLine: @escaping @Sendable (String, URL) throws -> Void = { line, url in
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
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

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    public func all() -> [ActivitySample] {
        guard let text = try? read(fileURL) else { return [] }
        let (_, dec) = Self.coder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(ActivitySample.self, from: Data($0.utf8))
        }
    }

    public func append(_ sample: ActivitySample) throws {
        let (enc, _) = Self.coder()
        try appendLine(String(decoding: try enc.encode(sample), as: UTF8.self) + "\n", fileURL)
    }

    /// Drops samples older than the 7-day window. Best-effort; a failed rewrite
    /// just leaves stale rows for the next prune.
    public func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let kept = all().filter { $0.ts >= cutoff }
        let (enc, _) = Self.coder()
        let body = (try? kept.map { String(decoding: try enc.encode($0), as: UTF8.self) }
            .joined(separator: "\n")) ?? ""
        try? overwrite(body.isEmpty ? "" : body + "\n", fileURL)
    }
}

/// An AI daily narrative for one day. Stored in the sidecar, not the markdown,
/// because the markdown is regenerated whole.
public struct DaySummary: Codable, Equatable, Sendable {
    public var day: String
    public var summary: String
    public var generatedAt: Date

    public init(day: String, summary: String, generatedAt: Date) {
        self.day = day
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

/// Append-only sidecar of day summaries; the newest line for a day wins.
public struct DaySummaryStore: Sendable {
    public let fileURL: URL
    private let read: @Sendable (URL) throws -> String
    private let appendLine: @Sendable (String, URL) throws -> Void
    private let overwrite: @Sendable (String, URL) throws -> Void

    public init(
        fileURL: URL,
        read: @escaping @Sendable (URL) throws -> String = { try String(contentsOf: $0, encoding: .utf8) },
        appendLine: @escaping @Sendable (String, URL) throws -> Void = { line, url in
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
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

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    public func all() -> [DaySummary] {
        guard let text = try? read(fileURL) else { return [] }
        let (_, dec) = Self.coder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(DaySummary.self, from: Data($0.utf8))
        }
    }

    public func upsert(day: String, summary: String, generatedAt: Date) throws {
        let (enc, _) = Self.coder()
        let record = DaySummary(day: day, summary: summary, generatedAt: generatedAt)
        try appendLine(String(decoding: try enc.encode(record), as: UTF8.self) + "\n", fileURL)
    }

    /// day -> newest summary text, for merging into the work-log markdown.
    public func byDay() -> [String: String] {
        var out: [String: String] = [:]
        for record in all() { out[record.day] = record.summary }  // later lines win
        return out
    }
}

/// One task's estimate-vs-actual for the day, fed to the summarizer.
public struct EstimateDelta: Equatable, Sendable {
    public var taskTitle: String
    public var estimatedMinutes: Int
    public var actualMinutes: Int

    public init(taskTitle: String, estimatedMinutes: Int, actualMinutes: Int) {
        self.taskTitle = taskTitle
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
    }
}

/// The end-of-day summary adapter. DrawerCore owns the protocol; the
/// FoundationModels implementation lives in the app behind a conditional import.
public protocol DaySummarizer: Sendable {
    func summarize(day: String, sessions: [WorkSession], deltas: [EstimateDelta]) async throws -> String
}
