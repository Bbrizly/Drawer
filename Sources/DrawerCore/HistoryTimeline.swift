import Foundation

/// One captured state: when it was taken and the raw markdown at that instant.
public struct TimelineSnapshot: Sendable {
    public var ts: Date
    public var markdown: String
    public init(ts: Date, markdown: String) {
        self.ts = ts
        self.markdown = markdown
    }
}

public enum TaskEventKind: Equatable, Sendable {
    case appeared, checkedOff, removed
}

/// A single change between adjacent snapshots, anchored to the snapshot's `ts`.
/// The scrubber highlights the events whose `ts` matches the step it lands on.
public struct TimelineEvent: Equatable, Sendable {
    public var ts: Date
    public var identity: String
    public var title: String
    public var kind: TaskEventKind
    public init(ts: Date, identity: String, title: String, kind: TaskEventKind) {
        self.ts = ts
        self.identity = identity
        self.title = title
        self.kind = kind
    }
}

/// A task's whole life across the retained window. `identity` is the normalized
/// title, so a task keeps one lifecycle as it gets checked, re-opened, or
/// carried across days; `survival` is how long it stayed visible.
public struct TaskLifecycle: Equatable, Sendable {
    public var identity: String
    public var title: String
    public var firstSeen: Date
    public var lastSeen: Date
    public var completedAt: Date?
    public var survival: TimeInterval { lastSeen.timeIntervalSince(firstSeen) }
    public init(identity: String, title: String, firstSeen: Date, lastSeen: Date, completedAt: Date?) {
        self.identity = identity
        self.title = title
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.completedAt = completedAt
    }
}

public struct HistoryTimeline: Equatable, Sendable {
    public var events: [TimelineEvent]
    /// Every task ever seen, sorted by survival (longest first) for the
    /// "which tasks stayed longest" insight.
    public var lifecycles: [TaskLifecycle]
    public init(events: [TimelineEvent], lifecycles: [TaskLifecycle]) {
        self.events = events
        self.lifecycles = lifecycles
    }
}

/// One calendar day's tallies: how many tasks first showed up and how many got
/// checked off that day. `day` is the local start-of-day the counts belong to.
public struct DayTally: Equatable, Sendable {
    public var day: Date
    public var started: Int
    public var completed: Int
    public init(day: Date, started: Int, completed: Int) {
        self.day = day
        self.started = started
        self.completed = completed
    }
}

/// Diffs a series of drawer snapshots into per-task lifecycle events. Pure and
/// single-pass over the snapshots; identity ignores the checkbox marker and the
/// `(Nm)` hint (both stripped by `TodoParser`/`TitleSimilarity.normalize`), so
/// checking a task reads as a state change, never remove+add.
public enum HistoryTimelineBuilder {
    public static func build(snapshots: [TimelineSnapshot]) -> HistoryTimeline {
        // identity -> (display title, done?) present in a snapshot.
        // Identity is the normalized title, so two identical task lines
        // collapse into one lifecycle (done if either is done); there is no
        // stable per-occurrence id to tell them apart.
        func state(_ markdown: String) -> [String: (title: String, done: Bool)] {
            var out: [String: (String, Bool)] = [:]
            for item in TodoParser.parse(markdown).flatMap(\.items) {
                let key = TitleSimilarity.normalize(item.title)
                let done = (out[key]?.1 ?? false) || item.isDone
                out[key] = (out[key]?.0 ?? item.title, done)
            }
            return out
        }

        var events: [TimelineEvent] = []
        var life: [String: TaskLifecycle] = [:]
        var previous: [String: (title: String, done: Bool)] = [:]

        // Diffing assumes chronological order; sort defensively so an unsorted
        // caller can't produce negative survival or scrambled events.
        for snapshot in snapshots.sorted(by: { $0.ts < $1.ts }) {
            let current = state(snapshot.markdown)
            for (identity, value) in current.sorted(by: { $0.key < $1.key }) {
                let wasPresent = previous[identity] != nil
                if !wasPresent {
                    events.append(TimelineEvent(ts: snapshot.ts, identity: identity, title: value.title, kind: .appeared))
                    // Reappearance keeps the original firstSeen/completedAt, so a
                    // task removed and re-added still reads as one long life.
                    if life[identity] == nil {
                        life[identity] = TaskLifecycle(
                            identity: identity, title: value.title,
                            firstSeen: snapshot.ts, lastSeen: snapshot.ts, completedAt: nil)
                    } else {
                        life[identity]?.lastSeen = snapshot.ts
                        life[identity]?.title = value.title
                    }
                } else {
                    life[identity]?.lastSeen = snapshot.ts
                    life[identity]?.title = value.title
                }
                let wasDone = previous[identity]?.done ?? false
                if value.done, !wasDone {
                    events.append(TimelineEvent(ts: snapshot.ts, identity: identity, title: value.title, kind: .checkedOff))
                    if life[identity]?.completedAt == nil { life[identity]?.completedAt = snapshot.ts }
                }
            }
            for (identity, value) in previous.sorted(by: { $0.key < $1.key }) where current[identity] == nil {
                events.append(TimelineEvent(ts: snapshot.ts, identity: identity, title: value.title, kind: .removed))
            }
            previous = current
        }

        let lifecycles = life.values
            .sorted { $0.survival != $1.survival ? $0.survival > $1.survival : $0.identity < $1.identity }
        return HistoryTimeline(events: events, lifecycles: lifecycles)
    }

    /// Per-day counts of tasks started (first seen) and completed (first checked
    /// off), oldest day first. Counts distinct lifecycles, not raw events, so a
    /// task removed and re-added is not counted as started twice, and a task
    /// re-opened and re-checked is completed once (on its first check-off day).
    ///
    /// ponytail: whatever was already in the file at the first snapshot counts as
    /// "started" on that first day, because history has no view before it began.
    /// It reads as a baseline, not a spike; live enough that no fix is worth it.
    public static func dailySummary(_ timeline: HistoryTimeline, calendar: Calendar = .current) -> [DayTally] {
        var started: [Date: Int] = [:]
        var completed: [Date: Int] = [:]
        for life in timeline.lifecycles {
            started[calendar.startOfDay(for: life.firstSeen), default: 0] += 1
            if let done = life.completedAt {
                completed[calendar.startOfDay(for: done), default: 0] += 1
            }
        }
        return Set(started.keys).union(completed.keys)
            .map { DayTally(day: $0, started: started[$0] ?? 0, completed: completed[$0] ?? 0) }
            .sorted { $0.day < $1.day }
    }
}
