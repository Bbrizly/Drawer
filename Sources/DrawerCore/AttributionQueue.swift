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
    /// The block is shorter than the log will record; approving it would
    /// return a session that exists nowhere.
    case blockTooShort
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
        // The log drops sub-second sessions; surface that instead of returning
        // a session that was never written (the UI would offer a phantom undo).
        guard entry.blockEnd.timeIntervalSince(entry.blockStart) >= 1 else {
            try remove(id)
            throw AttributionError.blockTooShort
        }
        let taskID: String
        let title: String
        let kind: WorkSessionKind
        if let override {
            taskID = override.taskID; title = override.title; kind = .task
        } else if let tt = entry.proposed.taskTitle {
            // The title is the durable attribution key; a rule can name a task
            // that has since left the candidate list (checked off, archived),
            // so a missing taskID must not downgrade the time to unattributed.
            taskID = entry.proposed.taskID ?? ""; title = tt; kind = .task
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

    /// Empties the queue outright. Used on opt-out: the entries embed raw window
    /// titles, so disabling the feature must not leave them sitting on disk.
    public func clearQueue() throws {
        if !queue.all().isEmpty { try queue.replaceAll([]) }
    }

    /// Drops entries that have sat unreviewed for `days`. Evidence holds window
    /// titles, so the queue's retention matches the raw trail's 7-day ceiling: a
    /// week unreviewed means the review is not happening, and the titles go.
    public func expireStale(now: Date, days: Int = 7) throws {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let kept = queue.all().filter { $0.createdAt >= cutoff }
        if kept.count != queue.all().count { try queue.replaceAll(kept) }
    }

    /// Backs the review UI's undo: puts the entry back in the queue for
    /// re-review, then deletes the just-approved session. Restore-first, so a
    /// failure between the two steps leaves both sides present and the
    /// idempotent approve path resolves it, never a vanished block.
    public func undo(_ session: WorkSession, restoring entry: AttributionQueueEntry) throws {
        if !queue.all().contains(where: { $0.id == entry.id }) {
            try queue.append(entry)
        }
        try log.replaceAll(log.all().filter { $0.id != session.id })
    }

    private func remove(_ id: UUID) throws {
        try queue.replaceAll(queue.all().filter { $0.id != id })
    }
}
