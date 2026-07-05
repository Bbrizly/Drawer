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
    @Published private(set) var ruleStore: RuleStore

    private let raw: RawActivityStore
    private let service: AttributionService
    private let workLog: WorkSessionLog
    private let daySummaries: DaySummaryStore
    private let candidatesProvider: @MainActor () -> [TaskCandidate]
    private let manualSpansProvider: @MainActor (Date) -> [TimeRange]
    private let todayProvider: @MainActor () -> String
    private let rulesURL: URL

    private var sampler: ActivitySampler?
    private var buffer: [ActivitySample] = []
    private var boundaries: [SessionBoundary] = []
    private var lastProcessedEnd = Date.distantPast
    private var processing = false

    init(
        raw: RawActivityStore,
        service: AttributionService,
        workLog: WorkSessionLog,
        daySummaries: DaySummaryStore,
        rulesURL: URL,
        candidatesProvider: @escaping @MainActor () -> [TaskCandidate],
        manualSpansProvider: @escaping @MainActor (Date) -> [TimeRange],
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
        refreshPending()
    }

    /// Whether the on-device model can help right now (drives the two AI jobs).
    var foundationModelsAvailable: Bool { Drawer.foundationModelsAvailable() }

    // MARK: sampling lifecycle

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func start() {
        guard sampler == nil else { return }
        let sampler = ActivitySampler()
        sampler.onSample = { [weak self] in self?.ingest($0) }
        sampler.onBoundary = { [weak self] in self?.closeBoundary($0) }
        sampler.start()
        self.sampler = sampler
        isObserving = ActivitySampler.ensureAccessibilityTrust(prompt: false)
        raw.prune(now: Date())
    }

    func stop() {
        flush(streamEnd: Date())
        sampler?.stop()
        sampler = nil
        isObserving = false
        Task { await summarizeDay(todayProvider()) }  // end-of-session narrative
    }

    /// The end-of-day AI summary (spec 02): one Foundation Models call over the
    /// day's approved sessions, capped at 3 sentences, into the sidecar that the
    /// work-log markdown merges. Silently does nothing when FM is unavailable.
    func summarizeDay(_ day: String) async {
        guard let summarizer = makeDaySummarizerIfAvailable() else { return }
        let calendar = Calendar.current
        let formatter = DateFormatter()
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
        // Coalesce a title flap against the previous sample before persisting.
        if let last = buffer.last, last.bundleID == sample.bundleID,
           last.normalizedTitle == sample.normalizedTitle {
            return
        }
        buffer.append(sample)
        try? raw.append(sample)
    }

    private func closeBoundary(_ boundary: SessionBoundary) {
        boundaries.append(boundary)
        flush(streamEnd: Date())
    }

    /// Fold buffered samples into completed blocks and queue proposals for those
    /// that ended before now (the tail may still be open).
    private func flush(streamEnd: Date) {
        guard !processing else { return }
        let blocks = ActivitySessionizer.sessionize(
            samples: buffer, boundaries: boundaries, streamEnd: streamEnd)
        let cutoff = streamEnd.addingTimeInterval(-1)
        let completed = blocks.filter { $0.end > lastProcessedEnd && $0.end <= cutoff }
        guard !completed.isEmpty else { return }

        processing = true
        let candidates = candidatesProvider()
        let rules = ruleStore
        let matcher = makeTaskMatcherIfAvailable()  // read availability fresh
        Task { @MainActor in
            defer { processing = false }
            let classifier = TaskAttributionClassifier(ruleStore: rules, matcher: matcher)
            for block in completed {
                let residuals = block.subtracting(manualSpansProvider(block.start))
                for residual in residuals {
                    let match = await classifier.classify(block: residual, candidates: candidates)
                    try? service.enqueue(AttributionQueueEntry(
                        block: residual, proposed: match, candidates: candidates, createdAt: Date()))
                }
                lastProcessedEnd = max(lastProcessedEnd, block.end)
            }
            // Keep only the still-open tail so the buffer doesn't grow forever.
            buffer.removeAll { $0.ts <= lastProcessedEnd }
            boundaries.removeAll { $0.ts <= lastProcessedEnd }
            refreshPending()
        }
    }

    // MARK: review queue

    func pending() -> [AttributionQueueEntry] { service.pending() }

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

    func undo(_ session: WorkSession) {
        try? service.undo(session)
    }

    private func refreshPending() { pendingCount = service.pending().count }

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
