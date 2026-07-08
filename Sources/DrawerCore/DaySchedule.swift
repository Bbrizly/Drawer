import Foundation

/// One time block in a day's plan. Anchored to a live task by `originalID`
/// (`TodoItem.id`) when it was scheduled from an existing task; nil for a
/// brand-new suggestion. `normalizedTitle` and `sectionDate` are the fallback
/// anchors reconciliation uses when the unstable `TodoItem.id` has drifted.
public struct ScheduleBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var minutes: Int
    public var normalizedTitle: String
    public var originalID: String?
    public var sectionDate: String?
    public var reason: String?

    public init(
        id: UUID = UUID(), title: String, minutes: Int, normalizedTitle: String,
        originalID: String? = nil, sectionDate: String? = nil, reason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.normalizedTitle = normalizedTitle
        self.originalID = originalID
        self.sectionDate = sectionDate
        self.reason = reason
    }
}

/// A non-destructive timed agenda for one day. Accepting a plan writes this
/// sidecar; `Drawer.md` is never rewritten. `sourceFileHash` is the hash of the
/// task file at accept time, so reconciliation can tell when the file drifted
/// and flag the schedule as needing review.
public struct DaySchedule: Codable, Equatable, Sendable {
    public var date: String
    public var startTime: Date
    public var sourceFileHash: String
    public var blocks: [ScheduleBlock]
    public var needsReview: Bool

    public init(
        date: String, startTime: Date, sourceFileHash: String,
        blocks: [ScheduleBlock], needsReview: Bool = false
    ) {
        self.date = date
        self.startTime = startTime
        self.sourceFileHash = sourceFileHash
        self.blocks = blocks
        self.needsReview = needsReview
    }

    /// The default day-start seeded at accept time: `now` rounded UP to the next
    /// quarter hour, so the first block begins on a clean :00/:15/:30/:45.
    public static func defaultStart(now: Date = Date()) -> Date {
        let step: TimeInterval = 15 * 60
        let rounded = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    /// The clock start of each block, stacking durations from `startTime`.
    public func startTimes() -> [Date] {
        var out: [Date] = []
        var cursor = startTime
        for block in blocks {
            out.append(cursor)
            cursor = cursor.addingTimeInterval(TimeInterval(block.minutes) * 60)
        }
        return out
    }

    /// Re-attaches each block to the current live tasks. `needsReview` is set
    /// when the task file drifted from accept time (`currentHash` differs). A
    /// block links by exact `originalID` first, then by a one-to-one normalized
    /// title match; anything unresolved degrades to a plain agenda item rather
    /// than a dangling link.
    public func reconciled(against liveTasks: [TodoItem], currentHash: String) -> ResolvedSchedule {
        let starts = startTimes()
        let byID = Dictionary(liveTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var claimed: Set<String> = []

        func resolve(_ block: ScheduleBlock) -> BlockLink {
            guard let originalID = block.originalID else { return .unlinked }
            if let task = byID[originalID], claimed.insert(task.id).inserted {
                return .linked(taskID: task.id)
            }
            // Exact id first, then one unclaimed same-title task in the same
            // section. Section-scoping stops a drifted block from grabbing a
            // same-named backlog task; edited titles are not matched. O(n*m)
            // scan is fine for a day's worth of tasks.
            if let match = liveTasks.first(where: { task in
                !claimed.contains(task.id)
                    && TitleSimilarity.normalize(task.title) == block.normalizedTitle
                    && (block.sectionDate == nil || task.sectionDate == block.sectionDate)
            }) {
                claimed.insert(match.id)
                return .linked(taskID: match.id)
            }
            return .unlinked
        }

        let resolvedBlocks = zip(blocks, starts).map { block, start in
            ResolvedBlock(block: block, link: resolve(block), start: start)
        }
        return ResolvedSchedule(
            date: date, needsReview: currentHash != sourceFileHash, blocks: resolvedBlocks)
    }
}

extension DaySchedule {
    /// Builds the non-destructive schedule from an accepted (edited) planner
    /// draft. Link anchors are captured now, at accept time: `sectionDate` is
    /// pulled from the live task the entry points at so reconciliation can
    /// section-scope its title fallback later, and `normalizedTitle` is the
    /// stable fallback for when the unstable `TodoItem.id` drifts.
    public init(
        date: String, startTime: Date, sourceFileHash: String,
        draft entries: [PlanDraftEntry], liveTasks: [TodoItem]
    ) {
        let byID = Dictionary(liveTasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let blocks = entries.map { entry in
            ScheduleBlock(
                title: entry.title,
                minutes: entry.minutes,
                normalizedTitle: TitleSimilarity.normalize(entry.title),
                originalID: entry.taskID,
                sectionDate: entry.taskID.flatMap { byID[$0]?.sectionDate },
                reason: entry.reason)
        }
        self.init(
            date: date, startTime: startTime, sourceFileHash: sourceFileHash, blocks: blocks)
    }
}

/// Non-destructive schedule sidecar. Append-only, newest record per date wins,
/// mirroring `DaySummaryStore`; `Drawer.md` is never touched.
public typealias DayScheduleStore = JSONLStore<DaySchedule>

extension JSONLStore where Element == DaySchedule {
    public func save(_ schedule: DaySchedule) throws { try append(schedule) }

    /// The most recently saved schedule for a date, or nil if none.
    public func latest(for date: String) -> DaySchedule? {
        all().last { $0.date == date }
    }
}

/// Whether a resolved block points at a live task or is a plain agenda item.
public enum BlockLink: Equatable, Sendable {
    case linked(taskID: String)
    case unlinked
}

public struct ResolvedBlock: Equatable, Sendable {
    public var block: ScheduleBlock
    public var link: BlockLink
    public var start: Date

    public init(block: ScheduleBlock, link: BlockLink, start: Date) {
        self.block = block
        self.link = link
        self.start = start
    }
}

/// A `DaySchedule` re-attached to the current task file, ready to render.
public struct ResolvedSchedule: Equatable, Sendable {
    public var date: String
    public var needsReview: Bool
    public var blocks: [ResolvedBlock]

    public init(date: String, needsReview: Bool, blocks: [ResolvedBlock]) {
        self.date = date
        self.needsReview = needsReview
        self.blocks = blocks
    }
}
