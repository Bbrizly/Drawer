import Combine
import DrawerCore
import Foundation

/// Live driver for attribution: owns the sampler, folds its stream through the
/// pure DrawerCore engine, and lands proposals in the review queue. Nothing is
/// written to the work log here — only the review card's approve does that.
///
/// The fold heuristics are all in DrawerCore (unit-tested); this class is the
/// thin AppKit-facing orchestration. Runtime behavior needs device dogfooding.
@MainActor
final class AttributionController: ObservableObject {
    @Published private(set) var isObserving = false
    @Published private(set) var pendingCount = 0
    /// Cached queue and today's roll-up, refreshed on every mutation. The Work
    /// pane's body re-evaluates on every live sample (title flap rate), so it
    /// must read these instead of hitting the disk per evaluation.
    @Published private(set) var pendingEntries: [AttributionQueueEntry] = []
    @Published private(set) var todaySummary = WorkSummary(day: "", rows: [], total: 0, longest: nil)
    @Published private(set) var ruleStore: RuleStore
    /// The current frontmost observation and its momentary rule-stage guess,
    /// so the Work pane can show "Watching X → looks like Y" live. Both nil when
    /// not observing. The guess is the cheap rule stage only (no model call).
    @Published private(set) var liveSample: ActivitySample?
    @Published private(set) var liveGuess: ProposedMatch?

    private let raw: RawActivityStore
    private let service: AttributionService
    private let workLog: WorkSessionLog
    private let daySummaries: DaySummaryStore
    private let candidatesProvider: @MainActor () -> [TaskCandidate]
    private let manualSpansProvider: @MainActor (TimeRange) -> [TimeRange]
    private let todayProvider: @MainActor () -> String
    private let rulesURL: URL

    private var sampler: ActivitySampler?
    private var buffer: [ActivitySample] = []
    private var boundaries: [SessionBoundary] = []
    private var processing = false
    /// Bumped on opt-out so an async classify already in flight cannot enqueue
    /// window-title evidence back into a queue we just cleared.
    private var enqueueGeneration = 0

    init(
        raw: RawActivityStore,
        service: AttributionService,
        workLog: WorkSessionLog,
        daySummaries: DaySummaryStore,
        rulesURL: URL,
        candidatesProvider: @escaping @MainActor () -> [TaskCandidate],
        manualSpansProvider: @escaping @MainActor (TimeRange) -> [TimeRange],
        todayProvider: @escaping @MainActor () -> String
    ) {
        self.raw = raw
        self.service = service
        self.workLog = workLog
        self.daySummaries = daySummaries
        self.rulesURL = rulesURL
        self.candidatesProvider = candidatesProvider
        self.manualSpansProvider = manualSpansProvider
        self.todayProvider = todayProvider
        self.ruleStore = Self.loadRules(rulesURL)
        // Retention runs at launch, not only while sampling: the raw trail's
        // 7-day promise and the queue's stale-entry cap must hold even if the
        // feature never starts this session.
        raw.prune(now: Date())
        try? service.expireStale(now: Date())
        refreshPending()
    }

    /// Whether the on-device model can help right now (drives the two AI jobs).
    var foundationModelsAvailable: Bool { Drawer.foundationModelsAvailable() }

    // MARK: sampling lifecycle

    /// The single entry point: attribution rides Work Mode, so the app hands it a
    /// pure activation (see `attributionActivation`) whenever the work phase or the
    /// permission flag changes. Idempotent: a repeat activation is a no-op.
    func apply(_ activation: AttributionActivation) {
        switch activation {
        case .observe:    start()
        case .suspend:    standDown(summarize: false)
        case .endSession: standDown(summarize: true)
        }
    }

    /// Settings calls this right after an Accessibility grant. A sampler armed
    /// before trust existed is inert (its start() bailed), and no defaults or
    /// phase change follows a grant, so nothing else would revive it.
    func retryIfPermitted() {
        guard sampler != nil, !isObserving,
              ActivitySampler.ensureAccessibilityTrust(prompt: false) else { return }
        sampler?.stop()
        sampler = nil
        start()
    }

    /// Turning the feature off deletes every store of window titles immediately:
    /// the raw trail AND the review queue (its evidence embeds the same titles).
    /// The 7-day window is a ceiling, not a license to keep titles after opt-out.
    /// Un-flushed buffered samples are dropped, and the generation bump makes any
    /// classify already in flight discard its results instead of re-queuing them.
    func eraseRawTrail() {
        buffer = []
        boundaries = []
        enqueueGeneration += 1
        try? raw.replaceAll([])
        try? service.clearQueue()
        refreshPending()
    }

    private func start() {
        guard sampler == nil else { return }
        let sampler = ActivitySampler()
        sampler.onSample = { [weak self] in self?.ingest($0) }
        sampler.onBoundary = { [weak self] in self?.closeBoundary($0) }
        sampler.start()
        self.sampler = sampler
        isObserving = ActivitySampler.ensureAccessibilityTrust(prompt: false)
        raw.prune(now: Date())
    }

    /// Stop sampling. If we were observing, flush the open block into the review
    /// queue first so nothing is dropped. `summarize` is true only when Work Mode
    /// ends (not when a manual task merely pauses the watcher), so the end-of-day
    /// narrative fires once per work session, not on every task tap.
    private func standDown(summarize: Bool) {
        if sampler != nil {
            flush(streamEnd: Date())
            sampler?.stop()
            sampler = nil
            isObserving = false
            liveSample = nil
            liveGuess = nil
        }
        if summarize { Task { await summarizeDay(todayProvider()) } }
    }

    /// The end-of-day AI summary (spec 02): one Foundation Models call over the
    /// day's approved sessions, capped at 3 sentences, into the sidecar that the
    /// work-log markdown merges. Silently does nothing when FM is unavailable.
    func summarizeDay(_ day: String) async {
        guard let summarizer = makeDaySummarizerIfAvailable() else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        // POSIX locale: a Buddhist/Japanese system calendar would otherwise
        // parse "2026-07-06" into the wrong era and the summary would vanish.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        guard let dayDate = formatter.date(from: day) else { return }
        let sessions = workLog.all().filter { calendar.isDate($0.start, inSameDayAs: dayDate) }
        guard !sessions.isEmpty else { return }
        guard let text = try? await summarizer.summarize(day: day, sessions: sessions, deltas: []) else {
            return  // estimate-vs-actual deltas arrive with the planner (spec 03)
        }
        try? daySummaries.upsert(day: day, summary: text, generatedAt: Date())
    }

    // MARK: sample folding

    private func ingest(_ sample: ActivitySample) {
        // Keep the "watching X" title current on every sample (a cheap assign),
        // but only rescore the "→ looks like Y" guess on a real focus change.
        // A title flap is the same app, so the guess barely moves, and the
        // candidate rebuild + token scoring is main-thread work not worth doing
        // at flap rate.
        liveSample = sample
        // Coalesce a title flap against the previous sample before persisting
        // (the same predicate the tested batch helper uses).
        if let last = buffer.last, last.coalesces(with: sample) { return }
        liveGuess = ruleStore.liveGuess(for: sample, candidates: candidatesProvider())
        buffer.append(sample)
        try? raw.append(sample)
    }

    private func closeBoundary(_ boundary: SessionBoundary) {
        boundaries.append(boundary)
        flush(streamEnd: Date())
    }

    /// Fold buffered samples into blocks and queue proposals. flush fires only on
    /// session-ending events (idle/sleep/lock/stop), so every block is complete —
    /// queue them all. The snapshot is taken and the buffer reset synchronously
    /// so samples arriving during the async classify accumulate for the next
    /// flush instead of being lost or double-queued.
    private func flush(streamEnd: Date) {
        guard !processing, !buffer.isEmpty else { return }
        let samples = buffer
        let bounds = boundaries
        buffer = []
        boundaries = []
        processing = true
        let candidates = candidatesProvider()
        let rules = ruleStore
        let matcher = makeTaskMatcherIfAvailable()  // read availability fresh
        let generation = enqueueGeneration
        Task { @MainActor in
            defer {
                processing = false
                refreshPending()
                // A stand-down that arrived while this classify was in flight
                // found `processing` set and returned; if the sampler is gone
                // no future boundary will come, so drain what it left behind.
                if sampler == nil, !buffer.isEmpty { flush(streamEnd: Date()) }
            }
            let config = SessionizerConfig.default
            let blocks = ActivitySessionizer.sessionize(
                samples: samples, boundaries: bounds, streamEnd: streamEnd, config: config)
            let classifier = TaskAttributionClassifier(ruleStore: rules, matcher: matcher)
            for block in blocks {
                // Subtracting a manual span can leave slivers below the block
                // floor; they are noise, not reviewable work.
                for residual in block.subtracting(manualSpansProvider(block.range))
                where residual.range.duration >= config.minBlock {
                    let match = await classifier.classify(block: residual, candidates: candidates)
                    // Opt-out mid-classify cleared the queue; don't re-add titles.
                    guard generation == enqueueGeneration else { return }
                    try? service.enqueue(AttributionQueueEntry(
                        block: residual, proposed: match, candidates: candidates, createdAt: Date()))
                }
            }
        }
    }

    // MARK: review queue

    /// The tasks eligible for a manual reassign in the Work pane's review.
    func candidates() -> [TaskCandidate] { candidatesProvider() }

    func pending() -> [AttributionQueueEntry] { service.pending() }

    /// Re-reads the cached queue and today's roll-up. Called by panes on open,
    /// so a day rollover or an external file edit shows without a mutation.
    func refreshDerived() { refreshPending() }

    @discardableResult
    func approve(_ id: UUID, as override: (taskID: String, title: String)?) -> WorkSession? {
        let session = try? service.approve(id, as: override)
        refreshPending()
        return session
    }

    func reject(_ id: UUID) {
        try? service.reject(id)
        refreshPending()
    }

    func undo(_ session: WorkSession, restoring entry: AttributionQueueEntry) {
        try? service.undo(session, restoring: entry)
        refreshPending()
    }

    private func refreshPending() {
        pendingEntries = service.pending().sorted { $0.blockStart < $1.blockStart }
        pendingCount = pendingEntries.count
        todaySummary = workLog.summary(for: todayProvider())
    }

    // MARK: rules

    func addRule(_ rule: AttributionRule) {
        ruleStore.rules.append(rule)
        saveRules()
    }

    func removeRule(_ id: UUID) {
        ruleStore.rules.removeAll { $0.id == id }
        saveRules()
    }

    private func saveRules() {
        guard let data = try? JSONEncoder().encode(ruleStore) else { return }
        try? FileManager.default.createDirectory(
            at: rulesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: rulesURL, options: .atomic)
    }

    private static func loadRules(_ url: URL) -> RuleStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(RuleStore.self, from: data)
        else { return RuleStore() }
        return store
    }
}
