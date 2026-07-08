import XCTest
@testable import DrawerCore

private func evidence(app: String = "Xcode", titles: [String]) -> AttributionEvidence {
    AttributionEvidence(
        bundleID: "com.apple.dt.Xcode", appName: app, titles: titles,
        candidateTaskIDs: [], candidateTaskTitles: [])
}

private func candidate(_ id: String, _ title: String, priority: Bool = false) -> TaskCandidate {
    TaskCandidate(id: id, title: title, priority: priority)
}

final class ReassignShortlistTests: XCTestCase {
    /// Enough candidates that the "small set" shortcut does not swallow the split.
    private func padding(_ n: Int) -> [TaskCandidate] {
        (0..<n).map { candidate("pad\($0)", "Errand number \($0)") }
    }

    func testEvidenceTitleSurfacesDeepCandidateIntoTop() {
        let deep = candidate("deep", "Fix TodoParser crash")
        let candidates = padding(8) + [deep]
        let split = ReassignShortlist.split(
            evidence: evidence(titles: ["TodoParser.swift edited"]), candidates: candidates, limit: 5)
        XCTAssertTrue(split.top.contains { $0.id == "deep" }, "matching candidate should rank into top")
    }

    func testPriorityBeatsNonMatchingNonPriority() {
        let inProgress = candidate("wip", "Redesign onboarding", priority: true)
        let candidates = [inProgress] + padding(8)
        let split = ReassignShortlist.split(
            evidence: evidence(app: "Safari", titles: ["Airline booking"]), candidates: candidates, limit: 5)
        XCTAssertTrue(split.top.contains { $0.id == "wip" }, "priority candidate should surface into top")
    }

    func testSmallSetReturnsAllInTopEmptyRest() {
        let candidates = padding(6)  // limit 5 + 1 <= 5 + 2
        let split = ReassignShortlist.split(
            evidence: evidence(titles: ["nothing"]), candidates: candidates, limit: 5)
        XCTAssertEqual(split.top.count, 6)
        XCTAssertTrue(split.rest.isEmpty)
    }

    func testRestPreservesInputOrder() {
        let candidates = padding(10)
        let split = ReassignShortlist.split(
            evidence: evidence(titles: ["unrelated"]), candidates: candidates, limit: 5)
        let restIDs = split.rest.map(\.id)
        let inputOrder = candidates.map(\.id).filter { id in restIDs.contains(id) }
        XCTAssertEqual(restIDs, inputOrder, "rest must keep original input order")
    }

    func testTiesKeepInputOrder() {
        // No evidence overlap, no priority: every score is equal, so top must be
        // the first `limit` in input order.
        let candidates = padding(10)
        let split = ReassignShortlist.split(
            evidence: evidence(titles: ["zzz"]), candidates: candidates, limit: 5)
        XCTAssertEqual(split.top.map(\.id), candidates.prefix(5).map(\.id))
    }
}
