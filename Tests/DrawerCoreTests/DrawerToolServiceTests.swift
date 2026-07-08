import XCTest
@testable import DrawerCore

/// Mutable byte box so the @Sendable read/write closures share state in tests.
private final class FileBox: @unchecked Sendable {
    var data: Data
    init(_ text: String = "") { data = Data(text.utf8) }
    var text: String { String(data: data, encoding: .utf8) ?? "<non-utf8>" }
}

private func makeService(
    _ box: FileBox, log: WorkSessionLog? = nil, today: String = "2026-07-06"
) -> DrawerToolService {
    DrawerToolService(
        read: { box.data },
        write: { box.data = $0 },
        workLog: log ?? WorkSessionLog(
            fileURL: URL(fileURLWithPath: "/dev/null"),
            read: { _ in "" }, appendLine: { _, _ in }, overwrite: { _, _ in }
        ),
        today: { today }
    )
}

final class DrawerToolServiceTests: XCTestCase {
    // MARK: list_tasks

    func testListTasksBuckets() throws {
        let box = FileBox("""
        ## 2026-07-05
        - [ ] carried thing
        ## 2026-07-06
        - [ ] today thing (30m)
        - [x] today done
        ## 2026-07-08
        - [ ] upcoming thing
        ## Backlog
        - [ ] someday

        """)
        let svc = makeService(box)
        let all = try svc.listTasks(section: .all, includeDone: true)
        XCTAssertEqual(Set(all.map(\.section)), ["carried", "today", "upcoming", "backlog"])
        let today = all.first { $0.title == "today thing" }!
        XCTAssertEqual(today.minutes, 30)
        XCTAssertEqual(today.date, "2026-07-06")
        XCTAssertEqual(today.section, "today")
    }

    func testListTasksSectionFilterAndIncludeDone() throws {
        let box = FileBox("## 2026-07-06\n- [ ] a\n- [x] b\n")
        let svc = makeService(box)
        XCTAssertEqual(try svc.listTasks(section: .today, includeDone: false).map(\.title), ["a"])
        XCTAssertEqual(
            try svc.listTasks(section: .today, includeDone: true).map(\.title).sorted(), ["a", "b"]
        )
    }

    func testListTasksMissingFileIsEmpty() throws {
        let box = FileBox()
        box.data = Data() // empty == "missing"
        let svc = makeService(box)
        XCTAssertEqual(try svc.listTasks(section: .all, includeDone: true).count, 0)
    }

    func testListTasksNonUTF8Throws() {
        let box = FileBox()
        box.data = Data([0xFF, 0xFE])
        let svc = makeService(box)
        XCTAssertThrowsError(try svc.listTasks(section: .all, includeDone: true)) {
            XCTAssertEqual($0 as? DrawerToolError, .badEncoding)
        }
    }

    // MARK: add_task

    func testAddTaskToEmptyFileCreatesTodaySection() throws {
        let box = FileBox()
        let svc = makeService(box)
        let added = try svc.addTask(title: "new one", section: nil, date: nil, note: nil, minutes: 15)
        XCTAssertEqual(added.title, "new one")
        XCTAssertEqual(added.section, "today")
        XCTAssertEqual(box.text, "## 2026-07-06\n- [ ] new one (15m)\n")
    }

    func testAddTaskToBacklog() throws {
        let box = FileBox("## 2026-07-06\n- [ ] today\n")
        let svc = makeService(box)
        let added = try svc.addTask(
            title: "later", section: "backlog", date: nil, note: "when free", minutes: nil)
        XCTAssertEqual(added.section, "backlog")
        XCTAssertTrue(box.text.contains("## Backlog\n- [ ] later\n    when free\n"))
    }

    func testAddTaskToFutureDateInOrder() throws {
        let box = FileBox("## 2026-07-06\n- [ ] today\n\n## 2026-07-10\n- [ ] far\n")
        let svc = makeService(box)
        _ = try svc.addTask(title: "soon", section: nil, date: "2026-07-08", note: nil, minutes: nil)
        XCTAssertEqual(
            box.text,
            "## 2026-07-06\n- [ ] today\n\n## 2026-07-08\n- [ ] soon\n\n## 2026-07-10\n- [ ] far\n"
        )
    }

    func testAddTaskDateWinsOverSection() throws {
        // Both a date and a named section are supplied. The date must win: the
        // write target has to match the lookup key, so the call returns a DTO
        // dated to the day and never throws taskNotFound after a stray write.
        let box = FileBox("## 2026-07-06\n- [ ] today\n")
        let svc = makeService(box)
        let added = try svc.addTask(
            title: "dated", section: "backlog", date: "2026-07-08", note: nil, minutes: nil)
        XCTAssertEqual(added.date, "2026-07-08")
        XCTAssertEqual(added.section, "upcoming")
        // The task must not have landed in the backlog section.
        XCTAssertFalse(box.text.contains("## Backlog"))
        XCTAssertTrue(try svc.listTasks(section: .backlog, includeDone: true).isEmpty)
    }

    func testAddTaskWithDurationLikeSuffixReturnsResolvableID() throws {
        // The parser strips "(30m)" from the stored title, so the returned DTO
        // must come from the written line, never a fabricated unresolvable id.
        let box = FileBox()
        let svc = makeService(box)
        let dto = try svc.addTask(
            title: "Ship it (30m)", section: nil, date: nil, note: nil, minutes: nil)
        XCTAssertEqual(dto.title, "Ship it")
        XCTAssertEqual(dto.minutes, 30)
        // The id round-trips: the client can act on what add_task returned.
        XCTAssertNoThrow(try svc.toggleTask(id: dto.id))
    }

    func testAddTaskRejectsOutOfRangeMinutes() {
        let svc = makeService(FileBox())
        XCTAssertThrowsError(
            try svc.addTask(title: "x", section: nil, date: nil, note: nil, minutes: 0))
        XCTAssertThrowsError(
            try svc.addTask(title: "x", section: "backlog", date: nil, note: nil, minutes: 999))
    }

    func testAddTaskRejectsCheckboxShapedNote() {
        let box = FileBox("## 2026-07-06\n- [ ] a\n")
        let svc = makeService(box)
        XCTAssertThrowsError(try svc.addTask(
            title: "real", section: "backlog", date: nil, note: "- [ ] injected", minutes: nil)
        ) {
            guard case PlanWriterError.invalidEntry = $0 else {
                return XCTFail("expected invalidEntry, got \($0)")
            }
        }
        XCTAssertEqual(box.text, "## 2026-07-06\n- [ ] a\n") // unwritten
    }

    func testAddTaskRejectsNewlineTitle() {
        let box = FileBox()
        let svc = makeService(box)
        XCTAssertThrowsError(try svc.addTask(
            title: "a\n## 2026-07-07", section: nil, date: nil, note: nil, minutes: nil))
        XCTAssertEqual(box.text, "")
    }

    // MARK: read-error handling

    func testNonNotFoundReadErrorPropagates() {
        struct Denied: Error {}
        let svc = DrawerToolService(
            read: { throw Denied() },
            write: { _ in XCTFail("must not write when the read failed") },
            workLog: WorkSessionLog(
                fileURL: URL(fileURLWithPath: "/dev/null"),
                read: { _ in "" }, appendLine: { _, _ in }, overwrite: { _, _ in }),
            today: { "2026-07-06" }
        )
        // A generic read failure is not "missing file": it must surface, not
        // masquerade as an empty drawer.
        XCTAssertThrowsError(try svc.listTasks(section: .all, includeDone: true)) {
            XCTAssertTrue($0 is Denied)
        }
    }

    func testMissingFileReadsEmptyPOSIX() throws {
        let svc = DrawerToolService(
            read: { throw CocoaError(.fileReadNoSuchFile) },
            write: { _ in },
            workLog: WorkSessionLog(
                fileURL: URL(fileURLWithPath: "/dev/null"),
                read: { _ in "" }, appendLine: { _, _ in }, overwrite: { _, _ in }),
            today: { "2026-07-06" }
        )
        XCTAssertEqual(try svc.listTasks(section: .all, includeDone: true).count, 0)
    }

    // MARK: concurrent-edit compare-and-swap

    func testWriteRecomputesOnConcurrentEdit() throws {
        // read #1 returns the old file; read #2 (the pre-write re-check) returns
        // a version an external editor grew. The plan must merge into the fresh
        // bytes, never clobber the externally-added task.
        final class Shifting: @unchecked Sendable {
            let reads = [
                Data("## 2026-07-06\n- [ ] a\n".utf8),
                Data("## 2026-07-06\n- [ ] a\n- [ ] b\n".utf8),
            ]
            var i = 0
            var written: Data?
            func read() -> Data { defer { i += 1 }; return reads[min(i, reads.count - 1)] }
        }
        let box = Shifting()
        let svc = DrawerToolService(
            read: { box.read() },
            write: { box.written = $0 },
            workLog: WorkSessionLog(
                fileURL: URL(fileURLWithPath: "/dev/null"),
                read: { _ in "" }, appendLine: { _, _ in }, overwrite: { _, _ in }),
            today: { "2026-07-06" }
        )
        _ = try svc.writeDayPlan(date: "2026-07-06", entries: [PlanEntry(title: "c")], replace: false)
        XCTAssertEqual(
            String(data: box.written ?? Data(), encoding: .utf8),
            "## 2026-07-06\n- [ ] a\n- [ ] b\n- [ ] c\n"
        )
    }

    // MARK: toggle_task

    func testToggleTaskByID() throws {
        let box = FileBox("## 2026-07-06\n- [ ] a\n- [ ] b\n")
        let svc = makeService(box)
        let tasks = try svc.listTasks(section: .today, includeDone: true)
        let b = tasks.first { $0.title == "b" }!
        let result = try svc.toggleTask(id: b.id)
        XCTAssertTrue(result.done)
        XCTAssertEqual(box.text, "## 2026-07-06\n- [ ] a\n- [x] b\n")
    }

    func testToggleStaleIDThrowsTaskNotFound() {
        let box = FileBox("## 2026-07-06\n- [ ] a\n")
        let svc = makeService(box)
        XCTAssertThrowsError(try svc.toggleTask(id: "2026-07-06|0|- [ ] gone")) {
            XCTAssertEqual($0 as? DrawerToolError, .taskNotFound("2026-07-06|0|- [ ] gone"))
        }
    }

    // MARK: get_work_summary

    func testWorkSummaryReportsMixedSource() throws {
        let logBox = LogBox()
        let log = makeMemoryLog(logBox)
        let s = Date(timeIntervalSince1970: 0)
        let day = dayFor(s)
        // Same task, both a manual span and an approved auto span => "mixed".
        try log.append(WorkSession(taskID: "t", taskTitle: "Ship", start: s, end: s.addingTimeInterval(600)))
        try log.append(WorkSession(taskID: "t", taskTitle: "Ship", start: s.addingTimeInterval(700), end: s.addingTimeInterval(1000), source: "auto"))
        try log.append(WorkSession(taskID: "u", taskTitle: "Email", start: s, end: s.addingTimeInterval(300), source: "auto"))
        let svc = makeService(FileBox(), log: log)
        let summary = svc.getWorkSummary(day: day)
        let ship = summary.rows.first { $0.title == "Ship" }!
        let email = summary.rows.first { $0.title == "Email" }!
        XCTAssertEqual(ship.source, "mixed")
        XCTAssertEqual(ship.seconds, 900)
        XCTAssertEqual(email.source, "auto")
        XCTAssertEqual(summary.totalSeconds, 1200)
        XCTAssertEqual(summary.longestTitle, "Ship")
    }

    func testWorkSummaryExcludesUnattributedTime() throws {
        let logBox = LogBox()
        let log = makeMemoryLog(logBox)
        let s = Date(timeIntervalSince1970: 0)
        let day = dayFor(s)
        try log.append(WorkSession(taskID: "t", taskTitle: "Ship", start: s, end: s.addingTimeInterval(600)))
        // Approved auto span that matched no task: must never inflate the summary.
        try log.append(WorkSession(
            taskID: "", taskTitle: "Unattributed", start: s.addingTimeInterval(700),
            end: s.addingTimeInterval(3000), source: "auto", kind: .unattributed))
        let svc = makeService(FileBox(), log: log)
        let summary = svc.getWorkSummary(day: day)
        XCTAssertNil(summary.rows.first { $0.title == "Unattributed" }, "unattributed leaked into summary")
        XCTAssertEqual(summary.totalSeconds, 600)
        XCTAssertEqual(summary.longestTitle, "Ship")
    }

    // MARK: write_day_plan

    func testWriteDayPlanAppendMergeKeepsChecked() throws {
        let box = FileBox("## 2026-07-06\n- [x] already done\n- [ ] keep me\n")
        let svc = makeService(box)
        let result = try svc.writeDayPlan(
            date: "2026-07-06",
            entries: [PlanEntry(title: "keep me"), PlanEntry(title: "fresh", minutes: 20)],
            replace: false
        )
        XCTAssertEqual(box.text, "## 2026-07-06\n- [x] already done\n- [ ] keep me\n- [ ] fresh (20m)\n")
        XCTAssertEqual(result.date, "2026-07-06")
        XCTAssertTrue(result.tasks.contains { $0.title == "fresh" })
    }

    func testWriteDayPlanReplaceScopeNeverErasesChecked() throws {
        let box = FileBox("## 2026-07-06\n- [x] done\n- [ ] old plan\n")
        let svc = makeService(box)
        _ = try svc.writeDayPlan(
            date: "2026-07-06", entries: [PlanEntry(title: "new plan")], replace: true)
        XCTAssertEqual(box.text, "## 2026-07-06\n- [x] done\n- [ ] new plan\n")
    }

    func testWriteDayPlanValidationRejectsOverCount() {
        let box = FileBox()
        let svc = makeService(box)
        let many = (1...13).map { PlanEntry(title: "t\($0)") }
        XCTAssertThrowsError(try svc.writeDayPlan(date: "2026-07-06", entries: many, replace: false)) {
            XCTAssertEqual($0 as? PlanWriterError, .tooManyEntries(13))
        }
        XCTAssertEqual(box.text, "") // unwritten
    }

    func testWriteDayPlanNonUTF8Refuses() {
        let box = FileBox()
        box.data = Data([0xFF, 0xFE])
        let svc = makeService(box)
        XCTAssertThrowsError(
            try svc.writeDayPlan(date: "2026-07-06", entries: [PlanEntry(title: "x")], replace: false)
        )
        XCTAssertEqual(box.data, Data([0xFF, 0xFE])) // never written
    }
}

private func dayFor(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = Calendar.current.timeZone
    return f.string(from: date)
}
