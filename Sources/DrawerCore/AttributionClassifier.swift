import Foundation

/// Stage 1 of attribution: deterministic rules. User substring rules first, then
/// token-overlap similarity between the block's window titles and candidate task
/// titles (the shared `TitleSimilarity`). No model, no writes.
public struct RuleStore: Codable, Equatable, Sendable {
    public var rules: [AttributionRule]

    public init(rules: [AttributionRule] = []) {
        self.rules = rules
    }

    /// The minimum similarity at which a title-overlap match is attached to a
    /// task. Below it, the block is left unattributed (no weak guess title).
    public static let suggestFloor = 0.5

    public func classify(block: ActivityBlock, candidates: [TaskCandidate]) -> ProposedMatch {
        // 1. An explicit user rule wins outright.
        if let rule = firstMatchingRule(block) {
            let target = TitleSimilarity.normalize(rule.taskTitle)
            let hit = candidates.first { TitleSimilarity.normalize($0.title) == target }
            return ProposedMatch(
                taskID: hit?.id, taskTitle: rule.taskTitle, confidence: 0.95,
                via: .rule, ruleID: rule.id.uuidString)
        }

        // 2. Strong token overlap between a window title and a task title.
        let scored = candidates.map { ($0, score(block, against: $0.title)) }
        guard let best = scored.max(by: { a, b in
            a.1 != b.1 ? a.1 < b.1 : (!a.0.priority && b.0.priority)  // score, then priority
        }) else {
            return ProposedMatch(taskID: nil, taskTitle: nil, confidence: 0, via: .none)
        }

        if best.1 >= Self.suggestFloor {
            return ProposedMatch(
                taskID: best.0.id, taskTitle: best.0.title, confidence: best.1, via: .rule)
        }
        return ProposedMatch(taskID: nil, taskTitle: nil, confidence: best.1, via: .none)
    }

    private func firstMatchingRule(_ block: ActivityBlock) -> AttributionRule? {
        rules.first { rule in
            let needle = rule.substring.lowercased()
            guard !needle.isEmpty else { return false }
            switch rule.field {
            case .bundleID:
                return block.bundleID.lowercased().contains(needle)
            case .title:
                return block.titles.contains { $0.lowercased().contains(needle) }
            }
        }
    }

    /// Best token-overlap of any of the block's titles against `title`.
    private func score(_ block: ActivityBlock, against title: String) -> Double {
        block.titles.map { TitleSimilarity.score($0, title) }.max() ?? 0
    }
}

/// Stage 2: the on-device model fallback. DrawerCore owns only the protocol; the
/// FoundationModels-backed implementation lives in the app target behind a
/// conditional import, so DrawerCore compiles and tests without the framework.
public protocol TaskMatcher: Sendable {
    func match(block: ActivityBlock, candidates: [TaskCandidate]) async throws -> ProposedMatch
}

/// Orchestrates the two stages: rules first, then the model only when rules
/// scored below the suggest floor AND a matcher is available. No matcher (no
/// Apple Intelligence) means the block simply stays as the rule stage left it.
public struct TaskAttributionClassifier: Sendable {
    public var ruleStore: RuleStore
    public var matcher: TaskMatcher?
    public var suggestFloor: Double

    public init(ruleStore: RuleStore, matcher: TaskMatcher?, suggestFloor: Double = RuleStore.suggestFloor) {
        self.ruleStore = ruleStore
        self.matcher = matcher
        self.suggestFloor = suggestFloor
    }

    public func classify(block: ActivityBlock, candidates: [TaskCandidate]) async -> ProposedMatch {
        let ruled = ruleStore.classify(block: block, candidates: candidates)
        if ruled.confidence >= suggestFloor { return ruled }
        guard let matcher else { return ruled }
        return (try? await matcher.match(block: block, candidates: candidates)) ?? ruled
    }
}
