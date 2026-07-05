import XCTest
@testable import DrawerCore

private func block(app: String, bundle: String, titles: [String]) -> ActivityBlock {
    ActivityBlock(
        start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 120),
        bundleID: bundle, appName: app, titles: titles)
}

private func candidate(_ id: String, _ title: String, priority: Bool = false) -> TaskCandidate {
    TaskCandidate(id: id, title: title, priority: priority)
}

/// A fake FM matcher so classifier stage 2 is testable with no FoundationModels.
private struct FakeMatcher: TaskMatcher {
    let result: ProposedMatch
    func match(block: ActivityBlock, candidates: [TaskCandidate]) async throws -> ProposedMatch {
        result
    }
}

final class AttributionClassifierTests: XCTestCase {
    func testUserRuleOnBundleIDMatches() {
        let store = RuleStore(rules: [
            AttributionRule(field: .bundleID, substring: "figma", taskTitle: "Design the board"),
        ])
        let match = store.classify(
            block: block(app: "Figma", bundle: "com.figma.Desktop", titles: ["Board — Figma"]),
            candidates: [candidate("t1", "Design the board"), candidate("t2", "Fix parser")])
        XCTAssertEqual(match.via, .rule)
        XCTAssertEqual(match.taskID, "t1")
        XCTAssertGreaterThanOrEqual(match.confidence, 0.85)
    }

    func testTitleOverlapMatchesCanonicalCase() {
        // The spec's canonical case: TodoParser.swift open, "Fix parser" a task.
        let store = RuleStore(rules: [])
        let match = store.classify(
            block: block(app: "Xcode", bundle: "com.apple.dt.Xcode", titles: ["TodoParser.swift — Drawer"]),
            candidates: [candidate("t1", "Fix parser"), candidate("t2", "Buy milk")])
        XCTAssertEqual(match.taskID, "t1")
        XCTAssertGreaterThanOrEqual(match.confidence, 0.5)
        XCTAssertEqual(match.via, .rule)
    }

    func testPriorityCandidateWinsCloseCall() {
        let store = RuleStore(rules: [])
        // Both titles overlap "report"; the in-progress one should win.
        let match = store.classify(
            block: block(app: "Pages", bundle: "com.apple.Pages", titles: ["Q3 report"]),
            candidates: [
                candidate("t1", "Q3 report draft"),
                candidate("t2", "Q3 report", priority: true),
            ])
        XCTAssertEqual(match.taskID, "t2")
    }

    func testNoOverlapIsUnattributed() {
        let store = RuleStore(rules: [])
        let match = store.classify(
            block: block(app: "Safari", bundle: "com.apple.Safari", titles: ["news headlines"]),
            candidates: [candidate("t1", "Fix parser")])
        XCTAssertNil(match.taskID)
        XCTAssertNil(match.taskTitle)
        XCTAssertEqual(match.via, MatchVia.none)
        XCTAssertLessThan(match.confidence, 0.5)
    }

    func testRoutingIsPresentationOnly() {
        XCTAssertEqual(QueueDisposition(confidence: 0.9), .preChecked)
        XCTAssertEqual(QueueDisposition(confidence: 0.7), .needsReview)
        XCTAssertEqual(QueueDisposition(confidence: 0.3), .unattributed)
        XCTAssertEqual(QueueDisposition(confidence: 0.85), .preChecked)
        XCTAssertEqual(QueueDisposition(confidence: 0.5), .needsReview)
    }

    func testClassifierUsesMatcherBelowFloor() async {
        let store = RuleStore(rules: [])
        let fmResult = ProposedMatch(taskID: "t9", taskTitle: "Model pick", confidence: 0.7, via: .model)
        let classifier = TaskAttributionClassifier(
            ruleStore: store, matcher: FakeMatcher(result: fmResult))
        // Rules find nothing here, so stage 2 (the fake matcher) is consulted.
        let match = await classifier.classify(
            block: block(app: "Safari", bundle: "com.apple.Safari", titles: ["random"]),
            candidates: [candidate("t1", "Fix parser")])
        XCTAssertEqual(match.via, .model)
        XCTAssertEqual(match.taskID, "t9")
    }

    func testClassifierWithoutMatcherKeepsRuleResult() async {
        let store = RuleStore(rules: [])
        let classifier = TaskAttributionClassifier(ruleStore: store, matcher: nil)
        let match = await classifier.classify(
            block: block(app: "Safari", bundle: "com.apple.Safari", titles: ["random"]),
            candidates: [candidate("t1", "Fix parser")])
        XCTAssertEqual(match.via, MatchVia.none) // FM unavailable => stays unattributed
    }

    func testStrongRuleSkipsMatcher() async {
        let store = RuleStore(rules: [])
        var called = false
        let spy = SpyMatcher { called = true }
        let classifier = TaskAttributionClassifier(ruleStore: store, matcher: spy)
        _ = await classifier.classify(
            block: block(app: "Xcode", bundle: "com.apple.dt.Xcode", titles: ["TodoParser.swift"]),
            candidates: [candidate("t1", "Fix parser")])
        XCTAssertFalse(called, "a confident rule match must not consult the model")
    }
}

private struct SpyMatcher: TaskMatcher {
    let onCall: @Sendable () -> Void
    func match(block: ActivityBlock, candidates: [TaskCandidate]) async throws -> ProposedMatch {
        onCall()
        return ProposedMatch(taskID: nil, taskTitle: nil, confidence: 0, via: .none)
    }
}
