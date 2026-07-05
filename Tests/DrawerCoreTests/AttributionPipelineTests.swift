import XCTest
@testable import DrawerCore

/// The smallest end-to-end proof of the pure pipeline: samples -> coalesce ->
/// sessionize -> subtract the manual stopwatch span -> classify -> enqueue ->
/// approve -> exactly one WorkSession(source: "auto"). No AX, no FM, no UI.
final class AttributionPipelineTests: XCTestCase {
    func testFullPipelineHonorsStopwatchInvariant() throws {
        // A one-hour Xcode stretch on TodoParser.swift, with a title flap.
        var samples: [ActivitySample] = []
        for ts in stride(from: 0.0, through: 3600.0, by: 120.0) {
            let title = ts == 240 ? "TodoParser.swift - Edited" : "TodoParser.swift"
            samples.append(ActivitySample(
                ts: Date(timeIntervalSince1970: ts), bundleID: "com.apple.dt.Xcode",
                appName: "Xcode", windowTitle: title))
        }

        // A manual stopwatch span from 09:10 to 09:20 (600s..1200s) already
        // logged. Attribution must NOT queue a competing match for that time.
        let logBox = LogBox()
        let log = makeMemoryLog(logBox)
        try log.append(WorkSession(
            taskID: "t1", taskTitle: "Fix parser",
            start: Date(timeIntervalSince1970: 600), end: Date(timeIntervalSince1970: 1200)))
        let manualSpan = TimeRange(
            start: Date(timeIntervalSince1970: 600), end: Date(timeIntervalSince1970: 1200))

        // Pipeline. Coalescing collapses the identical heartbeat samples; the
        // block runs to streamEnd (the ongoing focus up to "now" = 3600).
        let blocks = ActivitySessionizer.sessionize(
            samples: coalesceSamples(samples), streamEnd: Date(timeIntervalSince1970: 3600))
        XCTAssertEqual(blocks.count, 1)

        let residuals = blocks.flatMap { $0.subtracting([manualSpan]) }
        XCTAssertEqual(
            residuals.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] },
            [[0, 600], [1200, 3600]])

        let candidates = [TaskCandidate(id: "t1", title: "Fix parser", priority: true)]
        let store = RuleStore()
        let queueBox = QueueBox()
        let service = AttributionService(
            queue: memoryQueue(queueBox), log: log)
        for block in residuals {
            let match = store.classify(block: block, candidates: candidates)
            try service.enqueue(AttributionQueueEntry(
                block: block, proposed: match, candidates: candidates,
                createdAt: Date(timeIntervalSince1970: 0)))
        }
        XCTAssertEqual(service.pending().count, 2)

        // Approve the first residual (09:00-09:10). One auto session lands.
        let first = service.pending().sorted { $0.blockStart < $1.blockStart }.first!
        let session = try service.approve(first.id, as: nil)
        XCTAssertEqual(session.source, "auto")
        XCTAssertEqual(session.taskTitle, "Fix parser")
        XCTAssertEqual(session.end.timeIntervalSince1970, 600)

        // The log now has the manual span AND the approved auto span, and no
        // auto session covers the stopwatch interval 600..1200.
        let all = log.all()
        XCTAssertEqual(all.count, 2)
        let autos = all.filter { $0.source == "auto" }
        XCTAssertEqual(autos.count, 1)
        XCTAssertFalse(autos.contains { $0.start.timeIntervalSince1970 < 1200 && $0.end.timeIntervalSince1970 > 600 })
    }
}

private final class QueueBox: @unchecked Sendable { var text = "" }
private func memoryQueue(_ box: QueueBox) -> AttributionQueueStore {
    AttributionQueueStore(
        fileURL: URL(fileURLWithPath: "/dev/null"),
        read: { _ in box.text },
        appendLine: { line, _ in box.text += line },
        overwrite: { value, _ in box.text = value })
}
