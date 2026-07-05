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
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = Calendar.current.timeZone
    return f.string(from: date)
}
