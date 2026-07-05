import Foundation

/// A self-contained snapshot of why a block was proposed, embedded in the queue
/// entry so a row still explains itself after the 7-day raw trail is pruned.
public struct AttributionEvidence: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var titles: [String]
    public var candidateTaskIDs: [String]
    public var candidateTaskTitles: [String]

    public init(
        bundleID: String, appName: String, titles: [String],
        candidateTaskIDs: [String], candidateTaskTitles: [String]
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.titles = titles
        self.candidateTaskIDs = candidateTaskIDs
        self.candidateTaskTitles = candidateTaskTitles
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
/// (the queue holds only what still needs review).
public typealias AttributionQueueStore = JSONLStore<AttributionQueueEntry>

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
        // Idempotent: if a prior approve wrote the session but failed to clear the
        // queue entry, don't write it twice — just finish removing the entry.
        if let existing = log.all().first(where: { $0.attributionID == entry.id }) {
            try remove(id)
            return existing
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
