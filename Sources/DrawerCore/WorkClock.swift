import Foundation
import Observation

/// The live Work Mode engine. Counts up across many segments, attributes each to
/// a task title, and writes a `WorkSession` to the log every time a segment
/// closes. Modelled on `FocusTimer`: absolute `segmentStart`, a 0.5s ticker for
/// the display, and state that survives a relaunch.
@MainActor
@Observable
public final class WorkClock {
    public enum Phase: Equatable { case off, running, paused }

    public private(set) var phase: Phase = .off
    public private(set) var activeTaskID: String?
    public private(set) var activeTaskTitle: String = ""
    public private(set) var elapsed: TimeInterval = 0   // current segment only
    public private(set) var statusMessage: String?

    /// Logged time for the active task today, excluding the live segment.
    /// Tracked by Observation so a change on segment close refreshes the header
    /// even though `elapsed` also resets in the same breath.
    private(set) var cachedTodayTotal: TimeInterval = 0

    /// What the header shows: today's total on this task, live.
    public var activeTaskTotal: TimeInterval { cachedTodayTotal + elapsed }

    private let log: WorkSessionLog
    private let now: () -> Date
    private let calendar: Calendar
    private let defaults: UserDefaults
    private var segmentStart: Date?
    // nonisolated(unsafe) so the nonisolated deinit can tear these down. They
    // are only ever mutated on the main actor, so this is safe in practice.
    @ObservationIgnored nonisolated(unsafe) private var ticker: Timer?
    @ObservationIgnored nonisolated(unsafe) private var dayObserver: NSObjectProtocol?
    /// False while the panel is hidden. `elapsed` is display-only (segments
    /// close from absolute dates), so the 0.5s tick can stop entirely with no
    /// one looking and catch up from `segmentStart` when the panel returns.
    @ObservationIgnored private var displayActive = true

    /// Built once from the fixed `calendar` time zone. Day grouping happens on
    /// every segment close, so a fresh DateFormatter per call would be wasteful.
    /// Observation cannot wrap a `lazy` property, so the macro ignores it.
    @ObservationIgnored private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = calendar.timeZone
        return f
    }()

    /// A relaunch within this gap is treated as continuous (crash, quick quit).
    /// Anything longer is dropped rather than logged as work the user did not do.
    public static let resumeGraceSeconds: TimeInterval = 120

    private enum Key {
        static let on = "workMode.on"
        static let taskID = "workMode.activeTaskID"
        static let title = "workMode.activeTaskTitle"
        static let segStart = "workMode.segmentStart"
    }

    public init(
        log: WorkSessionLog,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.log = log
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
    }

    deinit {
        ticker?.invalidate()
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
    }

    public var isOn: Bool { phase != .off }

    /// Call when the panel shows (true) or hides (false). The midnight split
    /// observer is untouched, so day attribution stays exact while hidden.
    public func setDisplayActive(_ active: Bool) {
        guard active != displayActive else { return }
        displayActive = active
        guard phase == .running else { return }
        if active {
            tick() // catch the display up before the first visible frame
            startTicker()
        } else {
            stopTicker()
        }
    }

    private func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    // MARK: lifecycle

    /// Call on launch. Resumes a crash or quick-relaunch segment, drops a stale
    /// or overnight one so hours are never invented.
    public func restore() {
        guard defaults.bool(forKey: Key.on) else { return }
        observeMidnight()
        activeTaskID = defaults.string(forKey: Key.taskID)
        activeTaskTitle = defaults.string(forKey: Key.title) ?? ""
        cachedTodayTotal = log.total(
            forTitle: activeTaskTitle, on: dayString(now()), calendar: calendar)

        guard let started = defaults.object(forKey: Key.segStart) as? Date,
              activeTaskID != nil else {
            phase = .paused
            return
        }
        let n = now()
        let crossedDay = started < calendar.startOfDay(for: n)
        if crossedDay || n.timeIntervalSince(started) > Self.resumeGraceSeconds {
            statusMessage = "Work mode was left running. That open session was dropped."
            segmentStart = nil
            clearSegmentState()
            phase = .paused
        } else {
            segmentStart = started
            phase = .running
            startTicker()
        }
    }

    public func enter() {
        guard phase == .off else { return }
        phase = .paused
        statusMessage = nil
        defaults.set(true, forKey: Key.on)
        observeMidnight()
    }

    /// End Work Mode. Closes any open segment and returns today's summary.
    @discardableResult
    public func end(today: String) -> WorkSummary {
        closeSegment()
        let summary = log.summary(for: today, calendar: calendar)
        phase = .off
        activeTaskID = nil
        activeTaskTitle = ""
        elapsed = 0
        cachedTodayTotal = 0
        statusMessage = nil
        clearPersistedState()
        removeMidnightObserver()
        return summary
    }

    // MARK: tracking

    /// Start, or switch to, a task. Closes the previous segment first.
    public func track(taskID: String, title: String) {
        closeSegment()
        activeTaskID = taskID
        activeTaskTitle = title
        cachedTodayTotal = log.total(forTitle: title, on: dayString(now()), calendar: calendar)
        segmentStart = now()
        elapsed = 0
        phase = .running
        statusMessage = nil
        persistRunning()
        startTicker()
    }

    public func pause() {
        guard phase == .running else { return }
        closeSegment()          // folds the segment into cachedTodayTotal
        phase = .paused
    }

    public func resume() {
        guard phase == .paused, let id = activeTaskID, !activeTaskTitle.isEmpty else { return }
        track(taskID: id, title: activeTaskTitle)
    }

    /// Edit a task's logged total for a day, collapsing its sessions to one. Pass
    /// 0 to remove the task. Returns the refreshed summary so the card can update.
    @discardableResult
    public func editSummary(title: String, seconds: TimeInterval, on day: String) -> WorkSummary {
        // If the edited task is the one tracking right now, close its open segment
        // first so the live time is not double-counted on top of the edited total.
        if phase == .running, title == activeTaskTitle, day == dayString(now()) {
            closeSegment()
            phase = .paused
        }
        try? log.setTotal(forTitle: title, on: day, seconds: max(0, seconds), calendar: calendar)
        // Keep the live header honest if the edited task is the one being tracked.
        if day == dayString(now()) && title == activeTaskTitle {
            cachedTodayTotal = log.total(forTitle: title, on: day, calendar: calendar)
        }
        return log.summary(for: day, calendar: calendar)
    }

    /// Called by the UI when a task is checked off. If it is the tracked task,
    /// stop the clock so a finished task does not keep accruing time.
    public func taskCompleted(id: String, title: String) {
        guard phase != .off else { return }
        // Match by id only: a different task that merely shares a title should
        // not stop the clock.
        if id == activeTaskID { pause() }
    }

    /// Regenerates the markdown work log at `url` from the full session
    /// history. Call after anything that changes logged time so the file on
    /// disk stays in sync.
    public func exportMarkdown(to url: URL) {
        let markdown = renderWorkLogMarkdown(log.allSummaries(calendar: calendar))
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: internals

    /// Logs the open segment and stops counting. Idempotent. Updates the cached
    /// today-total so the paused header stays correct without re-reading the log.
    private func closeSegment() {
        stopTicker()
        defer {
            segmentStart = nil
            elapsed = 0
            clearSegmentState()
        }
        guard let start = segmentStart, let id = activeTaskID else { return }
        let session = WorkSession(
            taskID: id, taskTitle: activeTaskTitle, start: start, end: now())
        guard session.seconds >= 1 else { return }
        try? log.append(session)
        // Grouped by start day; only fold into today's cache if it is still
        // today (a midnight split has already handled the rollover).
        if dayString(start) == dayString(now()) {
            cachedTodayTotal += session.seconds
        }
    }

    private func persistRunning() {
        defaults.set(true, forKey: Key.on)
        defaults.set(activeTaskID, forKey: Key.taskID)
        defaults.set(activeTaskTitle, forKey: Key.title)
        defaults.set(segmentStart, forKey: Key.segStart)
    }

    private func clearSegmentState() {
        defaults.removeObject(forKey: Key.segStart)
    }

    private func clearPersistedState() {
        [Key.on, Key.taskID, Key.title, Key.segStart].forEach(defaults.removeObject)
    }

    private func observeMidnight() {
        guard dayObserver == nil else { return }
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.splitAtMidnight() }
        }
    }

    private func removeMidnightObserver() {
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
        dayObserver = nil
    }

    /// Close the segment (logged under the day it started) and reopen a fresh one
    /// so a session spanning midnight is counted per day. Internal, not private,
    /// so `@testable import` can drive it without faking the notification.
    func splitAtMidnight() {
        guard phase == .running, let id = activeTaskID else { return }
        let title = activeTaskTitle
        closeSegment()
        track(taskID: id, title: title)
    }

    private func startTicker() {
        stopTicker()
        guard displayActive else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running, let start = segmentStart else { return }
        // Clamp: a backward clock jump (NTP correction) must never show negative.
        elapsed = max(0, now().timeIntervalSince(start))
    }

    public nonisolated static func formatHM(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }
}
