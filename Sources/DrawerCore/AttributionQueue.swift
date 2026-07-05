import Foundation

/// A self-contained snapshot of why a block was proposed, embedded in the queue
/// entry so a row still explains itself after the 7-day raw trail is pruned.
public struct AttributionEvidence: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var titles: [String]
    public var candidateTaskIDs: [String]
    public var candidateTaskTitles: [String]
    public var matcherSummary: String?

    public init(
        bundleID: String, appName: String, titles: [String],
        candidateTaskIDs: [String], candidateTaskTitles: [String], matcherSummary: String? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.titles = titles
        self.candidateTaskIDs = candidateTaskIDs
        self.candidateTaskTitles = candidateTaskTitles
        self.matcherSummary = matcherSummary
    }
}

/// A pending, un-approved match. Lives in attribution-queue.jsonl, never in the
/// work log or the markdown until you approve it.
public struct AttributionQueueEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var blockStart: Date
    public var blockEnd: Date
    public var proposed: ProposedMatch
    public var evidence: AttributionEvidence

    public init(
        id: UUID = UUID(), createdAt: Date, blockStart: Date, blockEnd: Date,
        proposed: ProposedMatch, evidence: AttributionEvidence
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blockStart = blockStart
        self.blockEnd = blockEnd
        self.proposed = proposed
        self.evidence = evidence
    }

    public var disposition: QueueDisposition { QueueDisposition(confidence: proposed.confidence) }

    /// Builds a queue entry from a classified block, snapshotting the evidence
    /// (app, titles, candidates) so the row still explains itself after the
    /// 7-day raw trail is pruned.
    public init(
        block: ActivityBlock, proposed: ProposedMatch,
        candidates: [TaskCandidate], createdAt: Date
    ) {
        self.init(
            createdAt: createdAt, blockStart: block.start, blockEnd: block.end, proposed: proposed,
            evidence: AttributionEvidence(
                bundleID: block.bundleID, appName: block.appName, titles: block.titles,
                candidateTaskIDs: candidates.map(\.id), candidateTaskTitles: candidates.map(\.title)))
    }
}

/// Append-only JSONL of pending entries. Approving or rejecting removes an entry
/// (the queue holds only what still needs review). Injectable I/O, like
/// WorkSessionLog, so it runs in memory for tests.
public struct AttributionQueueStore: Sendable {
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

    public func all() -> [AttributionQueueEntry] {
        guard let text = try? read(fileURL) else { return [] }
        let (_, dec) = Self.coder()
        return text.split(separator: "\n").compactMap {
            try? dec.decode(AttributionQueueEntry.self, from: Data($0.utf8))
        }
    }

    public func append(_ entry: AttributionQueueEntry) throws {
        let (enc, _) = Self.coder()
        let line = String(decoding: try enc.encode(entry), as: UTF8.self) + "\n"
        try appendLine(line, fileURL)
    }

    public func replaceAll(_ entries: [AttributionQueueEntry]) throws {
        let (enc, _) = Self.coder()
        let body = try entries.map { String(decoding: try enc.encode($0), as: UTF8.self) }
            .joined(separator: "\n")
        try overwrite(body.isEmpty ? "" : body + "\n", fileURL)
    }
}

public enum AttributionError: Error, Equatable {
    case entryNotFound
}

/// The only path from a proposed match to the work log. Approve writes exactly
/// one WorkSession(source: "auto"); reject writes none; reassign writes against
/// the chosen task; undo deletes the written session.
public struct AttributionService: Sendable {
    private let queue: AttributionQueueStore
    private let log: WorkSessionLog

    public init(queue: AttributionQueueStore, log: WorkSessionLog) {
        self.queue = queue
        self.log = log
    }

    public func enqueue(_ entry: AttributionQueueEntry) throws {
        try queue.append(entry)
    }

    public func pending() -> [AttributionQueueEntry] {
        queue.all()
    }

    /// Approve (optionally reassigning to a different task). Writes one auto
    /// session and removes the entry from the queue. A proposal with no task and
    /// no override is approved as unattributed time (explicit marker).
    @discardableResult
    public func approve(
        _ id: UUID, as override: (taskID: String, title: String)?
    ) throws -> WorkSession {
        guard let entry = queue.all().first(where: { $0.id == id }) else {
            throw AttributionError.entryNotFound
        }
        let taskID: String
        let title: String
        let kind: WorkSessionKind
        if let override {
            taskID = override.taskID; title = override.title; kind = .task
        } else if let t = entry.proposed.taskID, let tt = entry.proposed.taskTitle {
            taskID = t; title = tt; kind = .task
        } else {
            taskID = ""; title = ""; kind = .unattributed
        }
        let session = WorkSession(
            taskID: taskID, taskTitle: title, start: entry.blockStart, end: entry.blockEnd,
            source: "auto", kind: kind, attributionID: entry.id)
        try log.append(session)
        try remove(id)
        return session
    }

    public func reject(_ id: UUID) throws {
        try remove(id)
    }

    /// Deletes a just-approved session by id (backs the review card's undo).
    public func undo(_ session: WorkSession) throws {
        try log.replaceAll(log.all().filter { $0.id != session.id })
    }

    private func remove(_ id: UUID) throws {
        try queue.replaceAll(queue.all().filter { $0.id != id })
    }
}
