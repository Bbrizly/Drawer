import Foundation

/// A half-open time interval `[start, end)`. Two ranges that only touch at an
/// endpoint do not overlap, so adjacent spans never double-count.
public struct TimeRange: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    /// This range trimmed to lie within `outer`, or nil if they don't overlap.
    public func clamped(to outer: TimeRange) -> TimeRange? {
        let s = max(start, outer.start)
        let e = min(end, outer.end)
        return s < e ? TimeRange(start: s, end: e) : nil
    }
}

/// One frontmost-app/window observation. Appended to raw-activity.jsonl.
public struct ActivitySample: Codable, Equatable, Sendable {
    public var ts: Date
    public var bundleID: String
    public var appName: String
    public var windowTitle: String?

    public init(ts: Date, bundleID: String, appName: String, windowTitle: String? = nil) {
        self.ts = ts
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
    }

    /// Normalized title for clustering; empty when the title was unreadable.
    public var normalizedTitle: String {
        windowTitle.map(TitleSimilarity.normalize) ?? ""
    }

    /// True when `next` is a title flap of this sample (same app, same
    /// normalized title): the pair coalesces to one persisted sample. The one
    /// definition both the batch helper and the live ingest use.
    public func coalesces(with next: ActivitySample) -> Bool {
        bundleID == next.bundleID && normalizedTitle == next.normalizedTitle
    }
}

/// An out-of-band event that forces the current block closed at `ts`
/// (sleep, screen lock) regardless of the idle tolerance.
public struct SessionBoundary: Equatable, Sendable {
    public var ts: Date
    public var reason: ActivityBlockCloseReason

    public init(ts: Date, reason: ActivityBlockCloseReason) {
        self.ts = ts
        self.reason = reason
    }
}

/// Why a block stopped growing. Recorded so sessionizer behavior is testable
/// from explicit boundary events, not hidden wall-clock timing.
public enum ActivityBlockCloseReason: String, Codable, Sendable {
    case idle, sleep, lock, appSwitch, endOfStream
}

/// How a match was produced. Never implies a write — it only labels the source.
public enum MatchVia: String, Codable, Sendable {
    case rule, model, none
}

/// A proposed (never auto-written) task match for one block. `taskID`/`taskTitle`
/// are nil for a genuinely unattributed block — no fake "Unattributed" title.
public struct ProposedMatch: Codable, Equatable, Sendable {
    public var taskID: String?
    public var taskTitle: String?
    public var confidence: Double
    public var via: MatchVia
    public var ruleID: String?

    public init(
        taskID: String?, taskTitle: String?, confidence: Double,
        via: MatchVia, ruleID: String? = nil
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.confidence = confidence
        self.via = via
        self.ruleID = ruleID
    }
}

/// A task eligible for matching. `priority` is true for in-progress and carried
/// tasks, which break near-ties in the classifier.
public struct TaskCandidate: Equatable, Sendable {
    public var id: String
    public var title: String
    public var priority: Bool

    public init(id: String, title: String, priority: Bool = false) {
        self.id = id
        self.title = title
        self.priority = priority
    }
}

/// A user matching rule: a substring on the bundle id or window title that maps
/// to a task title. Substring only in v1, no regex.
public struct AttributionRule: Codable, Equatable, Sendable, Identifiable {
    public enum Field: String, Codable, Sendable { case bundleID, title }
    public var id: UUID
    public var field: Field
    public var substring: String
    public var taskTitle: String

    public init(id: UUID = UUID(), field: Field, substring: String, taskTitle: String) {
        self.id = id
        self.field = field
        self.substring = substring
        self.taskTitle = taskTitle
    }
}

/// How a match presents in the review queue. Presentation only — it never
/// decides whether a session is written; approval does.
public enum QueueDisposition: String, Codable, Sendable {
    case preChecked   // >= 0.85: pre-checked for fast approve-all
    case needsReview  // 0.5 ..< 0.85: listed unchecked
    case unattributed // < 0.5: routed to the Unattributed bucket

    public init(confidence: Double) {
        if confidence >= 0.85 { self = .preChecked }
        else if confidence >= 0.5 { self = .needsReview }
        else { self = .unattributed }
    }
}

/// A continuous stretch of focus on one app whose window titles stayed in the
/// same cluster. The unit the classifier proposes a task match for.
public struct ActivityBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var bundleID: String
    public var appName: String
    public var titles: [String]
    public var normalizedTitles: [String]
    public var closeReason: ActivityBlockCloseReason?

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        bundleID: String,
        appName: String,
        titles: [String],
        normalizedTitles: [String]? = nil,
        closeReason: ActivityBlockCloseReason? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.bundleID = bundleID
        self.appName = appName
        self.titles = titles
        self.normalizedTitles = normalizedTitles ?? titles.map(TitleSimilarity.normalize)
        self.closeReason = closeReason
    }

    public var range: TimeRange { TimeRange(start: start, end: end) }

    /// A copy spanning `[start, end)`, keeping the app/title evidence but taking
    /// a fresh id so each residual is its own proposal.
    public func slice(start: Date, end: Date) -> ActivityBlock {
        ActivityBlock(
            start: start, end: end, bundleID: bundleID, appName: appName,
            titles: titles, normalizedTitles: normalizedTitles, closeReason: closeReason)
    }

    /// This block with `spans` removed: the residual blocks covering the time
    /// NOT claimed by those spans. This is the stopwatch-overlap invariant —
    /// attribution proposes only for the gaps a manual session didn't cover, so
    /// a block partly overlapping the stopwatch still contributes its unattended
    /// portion, and never a competing match for the stopwatch's own time.
    public func subtracting(_ spans: [TimeRange]) -> [ActivityBlock] {
        let base = range
        let clamped = spans.compactMap { $0.clamped(to: base) }.sorted { $0.start < $1.start }

        // Merge overlapping/adjacent exclusions so gaps compute cleanly.
        var merged: [TimeRange] = []
        for span in clamped {
            if var last = merged.last, last.end >= span.start {
                last.end = max(last.end, span.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(span)
            }
        }

        var result: [ActivityBlock] = []
        var cursor = base.start
        for span in merged {
            if cursor < span.start { result.append(slice(start: cursor, end: span.start)) }
            cursor = max(cursor, span.end)
        }
        if cursor < base.end { result.append(slice(start: cursor, end: base.end)) }
        return result
    }
}
