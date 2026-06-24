import Foundation

/// One continuous stretch of work on a single task. Persisted as one JSONL line.
public struct WorkSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: String      // TodoItem.id at capture time, best-effort only
    public let taskTitle: String   // the durable attribution key
    public let start: Date
    public let end: Date

    public init(id: UUID = UUID(), taskID: String, taskTitle: String, start: Date, end: Date) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.start = start
        self.end = end
    }

    public var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
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
