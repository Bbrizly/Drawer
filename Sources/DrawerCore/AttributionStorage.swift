import Foundation

/// Drops a sample whose app and normalized title match the previous kept one,
/// so a titlebar flapping between "file" and "file - Edited" writes one line,
/// not hundreds.
public func coalesceSamples(_ samples: [ActivitySample]) -> [ActivitySample] {
    var out: [ActivitySample] = []
    for sample in samples {
        if let last = out.last, last.coalesces(with: sample) { continue }
        out.append(sample)
    }
    return out
}

/// Append-only JSONL persistence with injectable I/O, so every store runs in
/// memory for tests. One implementation for the attribution sidecars; elements
/// round-trip via Codable with ISO-8601 dates.
public struct JSONLStore<Element: Codable & Sendable>: Sendable {
    public let fileURL: URL
    private let read: @Sendable (URL) throws -> String
    private let appendLine: @Sendable (String, URL) throws -> Void
    private let overwrite: @Sendable (String, URL) throws -> Void

    public init(
        fileURL: URL,
        read: @escaping @Sendable (URL) throws -> String = JSONLStore.diskRead,
        appendLine: @escaping @Sendable (String, URL) throws -> Void = JSONLStore.diskAppend,
        overwrite: @escaping @Sendable (String, URL) throws -> Void = JSONLStore.diskOverwrite
    ) {
        self.fileURL = fileURL
        self.read = read
        self.appendLine = appendLine
        self.overwrite = overwrite
    }

    public static var diskRead: @Sendable (URL) throws -> String {
        { try String(contentsOf: $0, encoding: .utf8) }
    }
    public static var diskAppend: @Sendable (String, URL) throws -> Void {
        { line, url in
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            // forUpdating (read+write): the torn-line check below must read the
            // last byte, and a write-only handle throws EBADF on read.
            let handle = try FileHandle(forUpdating: url)
            defer { try? handle.close() }
            // Repair a torn final line (a crash mid-append): ensure the file
            // ends with a newline first, so the new record never concatenates
            // onto a partial one and both get skipped as one corrupt line.
            let end = try handle.seekToEnd()
            if end > 0 {
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1) != Data("\n".utf8) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data("\n".utf8))
                }
                try handle.seekToEnd()
            }
            try handle.write(contentsOf: Data(line.utf8))
        }
    }
    public static var diskOverwrite: @Sendable (String, URL) throws -> Void {
        { value, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try value.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Every decodable element; a corrupt line is skipped, never fatal.
    public func all() -> [Element] {
        guard let text = try? read(fileURL) else { return [] }
        let (_, dec) = Self.coder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(Element.self, from: Data($0.utf8))
        }
    }

    public func append(_ element: Element) throws {
        let (enc, _) = Self.coder()
        try appendLine(String(decoding: try enc.encode(element), as: UTF8.self) + "\n", fileURL)
    }

    public func replaceAll(_ elements: [Element]) throws {
        let (enc, _) = Self.coder()
        let body = try elements.map { String(decoding: try enc.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
        try overwrite(body.isEmpty ? "" : body + "\n", fileURL)
    }
}

// MARK: raw-activity 7-day ring

/// Raw activity samples, kept to a 7-day window. Window titles can hold
/// sensitive text, so this is local-only and short-lived; it never reaches the
/// work log.
public typealias RawActivityStore = JSONLStore<ActivitySample>

extension JSONLStore where Element == ActivitySample {
    public static var retention: TimeInterval { 7 * 86400 }

    /// Drops samples older than the 7-day window. Best-effort; a failed rewrite
    /// just leaves stale rows for the next prune.
    public func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        try? replaceAll(all().filter { $0.ts >= cutoff })
    }
}

// MARK: day-summary sidecar

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

public typealias DaySummaryStore = JSONLStore<DaySummary>

extension JSONLStore where Element == DaySummary {
    public func upsert(day: String, summary: String, generatedAt: Date) throws {
        try append(DaySummary(day: day, summary: summary, generatedAt: generatedAt))
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
