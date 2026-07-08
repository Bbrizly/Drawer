import XCTest
@testable import DrawerCore

/// The Work pane's "looks like Y" hint: a momentary match from the *current*
/// sample, reusing the finished-block rule stage over a zero-length block. Only
/// the deterministic rule stage runs (no model), so it is cheap on every focus
/// change and testable without Apple Intelligence.
final class LiveGuessTests: XCTestCase {
    private func sample(_ bundle: String, _ app: String, _ title: String?) -> ActivitySample {
        ActivitySample(ts: Date(timeIntervalSince1970: 0), bundleID: bundle, appName: app, windowTitle: title)
    }

    func testUserRuleWinsAsLiveGuess() {
        let store = RuleStore(rules: [
            AttributionRule(field: .bundleID, substring: "xcode", taskTitle: "Ship the app")
        ])
        let candidates = [TaskCandidate(id: "1", title: "Ship the app")]

        let guess = store.liveGuess(
            for: sample("com.apple.dt.Xcode", "Xcode", "Drawer.swift"), candidates: candidates)

        XCTAssertEqual(guess.taskTitle, "Ship the app")
        XCTAssertEqual(guess.taskID, "1")
        XCTAssertEqual(guess.via, .rule)
    }

    func testStrongTitleOverlapProducesGuess() {
        let candidates = [TaskCandidate(id: "1", title: "Write the launch email")]

        let guess = store().liveGuess(
            for: sample("com.apple.mail", "Mail", "Write the launch email"), candidates: candidates)

        XCTAssertEqual(guess.taskTitle, "Write the launch email")
        XCTAssertGreaterThanOrEqual(guess.confidence, RuleStore.suggestFloor)
    }

    func testNoOverlapLeavesGuessUnattributed() {
        let candidates = [TaskCandidate(id: "1", title: "Refactor the parser")]

        let guess = store().liveGuess(
            for: sample("com.apple.Safari", "Safari", "cat videos"), candidates: candidates)

        XCTAssertNil(guess.taskTitle)
        XCTAssertEqual(guess.via, .none)
    }

    func testEmptyTitleStillReturnsAppLevelGuess() {
        // No readable window title: the guess falls through to unattributed
        // rather than crashing on the missing title.
        let guess = store().liveGuess(
            for: sample("com.apple.Safari", "Safari", nil),
            candidates: [TaskCandidate(id: "1", title: "Refactor the parser")])

        XCTAssertNil(guess.taskTitle)
    }

    private func store() -> RuleStore { RuleStore() }
}
