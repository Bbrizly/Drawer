import XCTest
@testable import DrawerCore

private final class Box: @unchecked Sendable { var text = "" }

private func memoryQueue(_ box: Box) -> AttributionQueueStore {
    AttributionQueueStore(
        fileURL: URL(fileURLWithPath: "/dev/null"),
        read: { _ in box.text },
        appendLine: { line, _ in box.text += line },
        overwrite: { value, _ in box.text = value })
}

private func entry(
    taskID: String?, taskTitle: String?, confidence: Double
) -> AttributionQueueEntry {
    AttributionQueueEntry(
        createdAt: Date(timeIntervalSince1970: 0),
        blockStart: Date(timeIntervalSince1970: 0),
        blockEnd: Date(timeIntervalSince1970: 600),
        proposed: ProposedMatch(
            taskID: taskID, taskTitle: taskTitle, confidence: confidence,
            via: taskID == nil ? .none : .rule),
        evidence: AttributionEvidence(
            bundleID: "com.apple.dt.Xcode", appName: "Xcode",
            titles: ["TodoParser.swift"], candidateTaskIDs: ["t1"], candidateTaskTitles: ["Fix parser"]))
}

final class AttributionQueueTests: XCTestCase {
    private func service() -> (AttributionService, Box, LogBox) {
        let qbox = Box(), lbox = LogBox()
        return (AttributionService(queue: memoryQueue(qbox), log: makeMemoryLog(lbox)), qbox, lbox)
    }

    func testPendingListsOnlyUnreviewed() throws {
        let (svc, _, _) = service()
        try svc.enqueue(entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9))
        try svc.enqueue(entry(taskID: nil, taskTitle: nil, confidence: 0.2))
        XCTAssertEqual(svc.pending().count, 2)
    }

    func testApproveWritesExactlyOneAutoSession() throws {
        let (svc, _, lbox) = service()
        let e = entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9)
        try svc.enqueue(e)
        let session = try svc.approve(e.id, as: nil)
        let log = makeMemoryLog(lbox)
        XCTAssertEqual(log.all().count, 1)
        XCTAssertEqual(session.source, "auto")
        XCTAssertEqual(session.taskTitle, "Fix parser")
        XCTAssertEqual(session.kind, .task)
        XCTAssertEqual(session.attributionID, e.id)
        XCTAssertTrue(svc.pending().isEmpty)          // left the queue
    }

    func testRejectWritesNoSession() throws {
        let (svc, _, lbox) = service()
        let e = entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9)
        try svc.enqueue(e)
        try svc.reject(e.id)
        XCTAssertEqual(makeMemoryLog(lbox).all().count, 0)
        XCTAssertTrue(svc.pending().isEmpty)
    }

    func testReassignWritesAgainstChosenTask() throws {
        let (svc, _, lbox) = service()
        let e = entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9)
        try svc.enqueue(e)
        let session = try svc.approve(e.id, as: (taskID: "t2", title: "Write tests"))
        XCTAssertEqual(session.taskTitle, "Write tests")
        XCTAssertEqual(session.taskID, "t2")
        XCTAssertEqual(makeMemoryLog(lbox).all().first?.taskTitle, "Write tests")
    }

    func testApproveUnattributedUsesMarkerNotFakeTitle() throws {
        let (svc, _, _) = service()
        let e = entry(taskID: nil, taskTitle: nil, confidence: 0.2)
        try svc.enqueue(e)
        let session = try svc.approve(e.id, as: nil)
        XCTAssertEqual(session.kind, .unattributed)
        XCTAssertEqual(session.taskTitle, "")   // never "Unattributed"
        XCTAssertFalse(session.isAttributable)
    }

    func testUndoDeletesTheWrittenSession() throws {
        let (svc, _, lbox) = service()
        let e = entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9)
        try svc.enqueue(e)
        let session = try svc.approve(e.id, as: nil)
        try svc.undo(session)
        XCTAssertEqual(makeMemoryLog(lbox).all().count, 0)
    }

    func testEvidenceSurvivesInQueueEntry() throws {
        let (svc, _, _) = service()
        let e = entry(taskID: "t1", taskTitle: "Fix parser", confidence: 0.9)
        try svc.enqueue(e)
        let stored = svc.pending().first!
        XCTAssertEqual(stored.evidence.appName, "Xcode")
        XCTAssertEqual(stored.evidence.titles, ["TodoParser.swift"])
    }

    func testWorkLogSummaryExcludesUnattributed() throws {
        let box = LogBox()
        let log = makeMemoryLog(box)
        let s = Date(timeIntervalSince1970: 0)
        try log.append(WorkSession(taskID: "t", taskTitle: "Ship", start: s, end: s.addingTimeInterval(600)))
        try log.append(WorkSession(
            taskID: "", taskTitle: "", start: s.addingTimeInterval(700), end: s.addingTimeInterval(1000),
            source: "auto", kind: .unattributed))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        let summary = log.summary(for: formatter.string(from: s))
        // The unattributed span is real logged time but not a task: it must not
        // appear as a (blank) row or inflate the per-task total.
        XCTAssertEqual(summary.rows.map(\.taskTitle), ["Ship"])
        XCTAssertEqual(summary.total, 600, accuracy: 0.001)
    }

    func testWorkSessionBackCompatWithoutKind() {
        let box = LogBox()
        box.text = """
        {"id":"00000000-0000-0000-0000-000000000009","taskID":"t","taskTitle":"A","start":"2026-07-05T10:00:00Z","end":"2026-07-05T10:10:00Z","source":"auto"}
        """ + "\n"
        let all = makeMemoryLog(box).all()
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all[0].kind)
        XCTAssertTrue(all[0].isAttributable)  // absent kind == task
    }
}
