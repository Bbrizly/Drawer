import Foundation

/// Builds the deterministic `PlanContext`. All timing is injected (calendar,
/// `today`), never read from the wall clock, so it is fully unit-testable with
/// synthetic tasks and sessions. Shared by the in-app FM planner and the MCP
/// planning path so both reason over identical facts.
public enum PlanContextBuilder {
    public static let defaultMinutes = 25
    public static let similarityFloor = 0.55
    public static let recentWindowDays = 14
    public static let capacityFallbackMinutes = 300
    public static let capacityRange = 60...480
    // A logged span under 30s is a stray tap, not a real run: it rounds to 0
    // minutes and would otherwise fake exact history predicting 0m.
    static let minRunSeconds: TimeInterval = 30
    static let minPredictedMinutes = 5

    public static func build(
        date: String,
        sections: [DaySection],
        today: String,
        sessions: [WorkSession],
        priorities: String? = nil,
        calendar: Calendar = .current,
        // ~400 tokens. Priorities are a ranking signal to weigh, not a doc to
        // read in full, and the model window is only 4096 tokens shared with the
        // task list and the drafted output, so the whole file must not dominate.
        maxPriorityChars: Int = 1500
    ) -> PlanContext {
        let openTasks = candidates(sections: sections, today: today, calendar: calendar)
        let actuals = taskActuals(sessions: sessions, calendar: calendar)
        let throughput = throughputStats(sessions: sessions, today: today, calendar: calendar)
        let calibration = openTasks.map { calibrate($0, actuals: actuals) }
        return PlanContext(
            date: date, openTasks: openTasks, throughput: throughput,
            calibration: calibration, priorities: priorityContext(priorities, maxChars: maxPriorityChars))
    }

    // MARK: candidates

    private static func candidates(
        sections: [DaySection], today: String, calendar: Calendar
    ) -> [PlanCandidateTask] {
        let display = TodoParser.display(sections: sections, today: today)
        var out: [PlanCandidateTask] = []
        func add(_ items: [TodoItem], _ section: PlanSection) {
            for item in items where !item.isDone {
                out.append(PlanCandidateTask(
                    id: item.id, title: item.title, section: section, minutesHint: item.minutes,
                    noteFirstLine: item.note?.split(separator: "\n").first.map(String.init),
                    isInProgress: item.isInProgress,
                    ageDays: ageDays(from: item.sectionDate, to: today, calendar: calendar)))
            }
        }
        add(display.today, .today)
        add(display.carried, .carried)
        add(display.upcoming, .upcoming)
        add(display.backlog, .backlog)
        return out
    }

    // MARK: per-task actuals (attributable only)

    struct TaskActual: Equatable {
        var title: String        // representative raw title, for similarity scoring
        var recentRuns: [Int]    // minutes, newest first, last 4
        var average: Double      // kept as Double so rounding to 5 doesn't lose the .5
    }

    private static func taskActuals(
        sessions: [WorkSession], calendar: Calendar
    ) -> [String: TaskActual] {
        let usable = sessions
            .filter { $0.isAttributable && $0.seconds >= minRunSeconds }
            .sorted { $0.end > $1.end }  // newest first
        var byTitle: [String: [WorkSession]] = [:]
        for session in usable {
            byTitle[TitleSimilarity.normalize(session.taskTitle), default: []].append(session)
        }
        return byTitle.mapValues { runs in
            let recent = Array(runs.prefix(4))
            let minutes = recent.map { Int(($0.seconds / 60).rounded()) }
            let average = minutes.isEmpty ? 0 : Double(minutes.reduce(0, +)) / Double(minutes.count)
            return TaskActual(title: recent.first?.taskTitle ?? "", recentRuns: minutes, average: average)
        }
    }

    // MARK: throughput / capacity

    private static func throughputStats(
        sessions: [WorkSession], today: String, calendar: Calendar
    ) -> ThroughputStats {
        let usable = sessions.filter { $0.isAttributable && $0.seconds >= minRunSeconds }
        var minutesByDay: [String: Int] = [:]
        let f = makeDayFormatter(calendar)  // one formatter, not one per session
        for session in usable {
            // Bucket by start, matching WorkSessionLog.summary, so a session that
            // crosses midnight isn't moved to the next day.
            let day = f.string(from: session.start)
            minutesByDay[day, default: 0] += Int((session.seconds / 60).rounded())
        }
        // -1: the window is `recentWindowDays` inclusive of today (today plus the
        // 13 days before it = 14), not today minus 14.
        let cutoff = cutoffDay(daysBefore: recentWindowDays - 1, from: today, calendar: calendar)
        var recentDays: [DailyThroughput] = []
        for (day, minutes) in minutesByDay where cutoff == nil || day >= cutoff! {
            recentDays.append(DailyThroughput(day: day, loggedMinutes: minutes))
        }
        recentDays.sort { $0.day > $1.day }

        let nonZero = recentDays.map(\.loggedMinutes).filter { $0 > 0 }
        let capacity: Int
        if nonZero.isEmpty {
            capacity = capacityFallbackMinutes
        } else {
            capacity = min(max(roundTo5(median(nonZero)), capacityRange.lowerBound), capacityRange.upperBound)
        }
        return ThroughputStats(recentDays: recentDays, realisticDailyCapacityMinutes: capacity)
    }

    // MARK: calibration

    private static func calibrate(_ task: PlanCandidateTask, actuals: [String: TaskActual]) -> TaskCalibration {
        let normalized = TitleSimilarity.normalize(task.title)

        // 1. Exact-title history wins.
        if let exact = actuals[normalized], !exact.recentRuns.isEmpty {
            let minutes = max(minPredictedMinutes, roundTo5(exact.average))
            return TaskCalibration(
                taskID: task.id, title: task.title, predictedMinutes: minutes,
                source: .exactHistory, evidence: "logged \(exact.recentRuns.count)×, avg ~\(minutes)m")
        }

        // 2. Token-overlap similar tasks (score >= floor), weighted top 3.
        var scored: [(actual: TaskActual, score: Double)] = []
        for actual in actuals.values {
            let score = TitleSimilarity.score(task.title, actual.title)
            if score >= similarityFloor { scored.append((actual, score)) }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.actual.title < $1.actual.title }
        let top = Array(scored.prefix(3))
        if !top.isEmpty {
            let weightSum = top.reduce(0.0) { $0 + $1.score }
            let weighted = top.reduce(0.0) { $0 + $1.actual.average * $1.score }
            let minutes = max(minPredictedMinutes, roundTo5(weighted / weightSum))
            return TaskCalibration(
                taskID: task.id, title: task.title, predictedMinutes: minutes,
                source: .similarHistory, evidence: "similar to \(top.count) past task(s), avg ~\(minutes)m")
        }

        // 3. The written (Nm) hint, else the 25m default. (A written "(25m)"
        // labels as default, but the predicted minutes are identical.)
        if task.minutesHint != defaultMinutes {
            return TaskCalibration(
                taskID: task.id, title: task.title, predictedMinutes: task.minutesHint,
                source: .writtenHint, evidence: "your \(task.minutesHint)m estimate")
        }
        return TaskCalibration(
            taskID: task.id, title: task.title, predictedMinutes: defaultMinutes,
            source: .defaultEstimate, evidence: "default \(defaultMinutes)m")
    }

    // MARK: priorities

    private static func priorityContext(_ text: String?, maxChars: Int) -> PrioritiesContext? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if text.count > maxChars {
            return PrioritiesContext(text: String(text.prefix(maxChars)), wasTruncated: true)
        }
        return PrioritiesContext(text: text, wasTruncated: false)
    }

    // MARK: date + math helpers

    /// Day keys are always Gregorian yyyy-MM-dd regardless of the system
    /// calendar; only the time zone follows the caller. Assigning the injected
    /// calendar would let a Buddhist or Japanese system calendar override the
    /// POSIX locale's Gregorian and read year 2569, diverging from today() and
    /// the section headings, so we force a Gregorian calendar here.
    private static func makeDayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var greg = Calendar(identifier: .gregorian)
        greg.timeZone = calendar.timeZone
        f.calendar = greg
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = calendar.timeZone
        return f
    }

    private static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        makeDayFormatter(calendar).string(from: date)
    }

    private static func parseDay(_ string: String, _ calendar: Calendar) -> Date? {
        makeDayFormatter(calendar).date(from: string)
    }

    private static func ageDays(from sectionDate: String, to today: String, calendar: Calendar) -> Int? {
        guard let from = parseDay(sectionDate, calendar), let to = parseDay(today, calendar) else { return nil }
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    private static func cutoffDay(daysBefore days: Int, from today: String, calendar: Calendar) -> String? {
        guard let date = parseDay(today, calendar),
              let cutoff = calendar.date(byAdding: .day, value: -days, to: date) else { return nil }
        return dayString(cutoff, calendar)
    }

    private static func median(_ values: [Int]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? Double(sorted[mid - 1] + sorted[mid]) / 2
            : Double(sorted[mid])
    }

    private static func roundTo5(_ value: Double) -> Int {
        Int((value / 5).rounded()) * 5
    }
}
