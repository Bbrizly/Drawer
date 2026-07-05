import Foundation

/// What kind of logged span this is. Absent/`.task` for real task work;
/// `.unattributed` for approved auto time that matched no task (an explicit
/// marker, never a fake title). The planner excludes `.unattributed` rows so
/// they never pollute calibration.
public enum WorkSessionKind: String, Codable, Sendable {
    case task, unattributed
}

/// One continuous stretch of work on a single task. Persisted as one JSONL line.
public struct WorkSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: String      // TodoItem.id at capture time, best-effort only
    public let taskTitle: String   // the durable attribution key
    public let start: Date
    public let end: Date
    /// How this session was captured: "auto" for an approved attribution match
    /// (spec 02), nil/absent for manual stopwatch time. Optional so every
    /// pre-existing log line still decodes; omitted from JSON when nil.
    public let source: String?
    /// Absent means a normal task session (back-compat). `.unattributed` marks
    /// approved auto time that matched no task.
    public let kind: WorkSessionKind?
    /// The `AttributionQueueEntry.id` this session was approved from, so an undo
    /// can find and delete exactly this row.
    public let attributionID: UUID?

    public init(
        id: UUID = UUID(), taskID: String, taskTitle: String,
        start: Date, end: Date, source: String? = nil,
        kind: WorkSessionKind? = nil, attributionID: UUID? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.start = start
        self.end = end
        self.source = source
        self.kind = kind
        self.attributionID = attributionID
    }

    public var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// True for sessions the planner may learn from: real task work, not
    /// approved-but-unattributed time.
    public var isAttributable: Bool { kind != .unattributed }
}

/// Per-task roll-up for one day. Identifiable by day so the view can present it
/// with `.sheet(item:)`.
public struct WorkSummary: Equatable, Identifiable, Sendable {
    public struct Row: Equatable, Sendable {
        public let taskTitle: String
        public let seconds: TimeInterval

        public init(taskTitle: String, seconds: TimeInterval) {
            self.taskTitle = taskTitle
            self.seconds = seconds
        }
    }

    public var id: String { day }
    public let day: String          // "yyyy-MM-dd"
    public let rows: [Row]          // longest first
    public let total: TimeInterval
    public let longest: WorkSession?

    public init(day: String, rows: [Row], total: TimeInterval, longest: WorkSession?) {
        self.day = day
        self.rows = rows
        self.total = total
        self.longest = longest
    }
}
