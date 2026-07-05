import XCTest
@testable import DrawerCore

private func session(_ title: String, day: String, minutes: Int, source: String? = nil, kind: WorkSessionKind? = nil) -> WorkSession {
    // Anchor at noon UTC on the given day.
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
    let start = f.date(from: day)!.addingTimeInterval(12 * 3600)
    return WorkSession(
        taskID: title, taskTitle: title, start: start,
        end: start.addingTimeInterval(Double(minutes) * 60), source: source, kind: kind)
}

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
}

final class PlanContextBuilderTests: XCTestCase {
    private func build(
        _ text: String, date: String = "2026-07-06", today: String = "2026-07-06",
        sessions: [WorkSession] = [], priorities: String? = nil
    ) -> PlanContext {
        PlanContextBuilder.build(
            date: date, sections: TodoParser.parse(text), today: today,
            sessions: sessions, priorities: priorities, calendar: utc)
    }

    // MARK: candidate gathering

    func testGathersOpenTasksBySection() {
        let ctx = build("""
        ## 2026-07-04
        - [ ] carried thing
        ## 2026-07-06
        - [/] in progress (45m)
        - [x] done today
        ## Backlog
        - [ ] someday
        """)
        let bySection = Dictionary(grouping: ctx.openTasks, by: \.section).mapValues { $0.map(\.title) }
        XCTAssertEqual(bySection[.carried], ["carried thing"])
        XCTAssertEqual(bySection[.today], ["in progress"])
        XCTAssertEqual(bySection[.backlog], ["someday"])
        let inProgress = ctx.openTasks.first { $0.title == "in progress" }!
        XCTAssertTrue(inProgress.isInProgress)
        XCTAssertEqual(inProgress.minutesHint, 45)
        XCTAssertEqual(ctx.openTasks.first { $0.title == "carried thing" }?.ageDays, 2)
    }

    // MARK: capacity

    func testCapacityIsMedianOfNonZeroDays() {
        let sessions = [
            session("a", day: "2026-07-05", minutes: 120),
            session("b", day: "2026-07-04", minutes: 300),
            session("c", day: "2026-07-03", minutes: 240),
        ]
        let ctx = build("## 2026-07-06\n- [ ] x\n", sessions: sessions)
        // median(120, 240, 300) = 240
        XCTAssertEqual(ctx.throughput.realisticDailyCapacityMinutes, 240)
    }

    func testCapacityFallbackWithNoHistory() {
        XCTAssertEqual(build("## 2026-07-06\n- [ ] x\n").throughput.realisticDailyCapacityMinutes, 300)
    }

    // MARK: calibration precedence

    func testExactHistoryWins() {
        let sessions = [
            session("Fix parser", day: "2026-07-01", minutes: 60),
            session("Fix parser", day: "2026-07-03", minutes: 80),
        ]
        let ctx = build("## 2026-07-06\n- [ ] Fix parser (25m)\n", sessions: sessions)
        let cal = ctx.calibration.first { $0.title == "Fix parser" }!
        XCTAssertEqual(cal.source, .exactHistory)
        XCTAssertEqual(cal.predictedMinutes, 70) // avg(60,80)=70
    }

    func testSimilarHistoryWhenNoExact() {
        let sessions = [session("Onboarding bug cleanup", day: "2026-07-02", minutes: 90)]
        let ctx = build("## 2026-07-06\n- [ ] Fix onboarding bug\n", sessions: sessions)
        let cal = ctx.calibration.first!
        XCTAssertEqual(cal.source, .similarHistory)
        XCTAssertEqual(cal.predictedMinutes, 90)
    }

    func testExactHistoryAverageRoundsNotTruncates() {
        let sessions = [
            session("Fix parser", day: "2026-07-01", minutes: 20),
            session("Fix parser", day: "2026-07-03", minutes: 25),
        ]
        let ctx = build("## 2026-07-06\n- [ ] Fix parser\n", sessions: sessions)
        // avg(20,25)=22.5 -> round to nearest 5 -> 25, not 20.
        XCTAssertEqual(ctx.calibration.first?.predictedMinutes, 25)
    }

    func testThroughputBucketsBySessionStart() {
        // 23:30 -> 00:30 crosses midnight; the hour counts on the start day.
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone(identifier: "UTC")
        let start = f.date(from: "2026-07-05 23:30")!
        let crossMidnight = WorkSession(
            taskID: "t", taskTitle: "t", start: start, end: start.addingTimeInterval(3600))
        let ctx = build("## 2026-07-06\n- [ ] x\n", sessions: [crossMidnight])
        XCTAssertEqual(ctx.throughput.recentDays.first?.day, "2026-07-05")
        XCTAssertEqual(ctx.throughput.recentDays.first?.loggedMinutes, 60)
    }

    func testWrittenHintWhenNoHistory() {
        let ctx = build("## 2026-07-06\n- [ ] Novel task (40m)\n")
        let cal = ctx.calibration.first!
        XCTAssertEqual(cal.source, .writtenHint)
        XCTAssertEqual(cal.predictedMinutes, 40)
    }

    func testDefaultWhenNoHistoryNoHint() {
        let ctx = build("## 2026-07-06\n- [ ] Bare task\n")
        let cal = ctx.calibration.first!
        XCTAssertEqual(cal.source, .defaultEstimate)
        XCTAssertEqual(cal.predictedMinutes, 25)
    }

    func testUnattributedSessionsExcludedFromCalibrationAndCapacity() {
        let sessions = [
            session("Fix parser", day: "2026-07-03", minutes: 200, source: "auto", kind: .unattributed),
            session("Fix parser", day: "2026-07-03", minutes: 60),
        ]
        let ctx = build("## 2026-07-06\n- [ ] Fix parser\n", sessions: sessions)
        let cal = ctx.calibration.first!
        // Only the 60m attributable run counts; the 200m unattributed is ignored.
        XCTAssertEqual(cal.predictedMinutes, 60)
        XCTAssertEqual(ctx.throughput.recentDays.first?.loggedMinutes, 60)
    }

    // MARK: priorities

    func testPrioritiesTruncated() {
        let long = String(repeating: "x", count: 5000)
        let ctx = PlanContextBuilder.build(
            date: "2026-07-06", sections: [], today: "2026-07-06", sessions: [],
            priorities: long, calendar: utc, maxPriorityChars: 100)
        XCTAssertEqual(ctx.priorities?.text.count, 100)
        XCTAssertTrue(ctx.priorities?.wasTruncated == true)
    }

    func testEmptyPrioritiesSkipped() {
        XCTAssertNil(build("## 2026-07-06\n- [ ] x\n", priorities: "   ").priorities)
        XCTAssertNil(build("## 2026-07-06\n- [ ] x\n", priorities: nil).priorities)
    }

    // MARK: end-to-end vertical slice

    func testCoreSliceBuildsFakePlansAndCommitsThroughPlanWriter() throws {
        struct FakePlanner: DayPlanner {
            func draft(context: PlanContext) async throws -> PlanDraft {
                PlanDraft(entries: context.openTasks.prefix(2).map { task in
                    let minutes = context.calibration.first { $0.taskID == task.id }?.predictedMinutes ?? 25
                    return PlanDraftEntry(title: task.title, taskID: task.id, minutes: minutes, reason: "picked")
                }, capacityNote: "you average ~5h")
            }
        }
        let file = "## 2026-07-06\n- [x] already done\n\n## Backlog\n- [ ] ship it\n- [ ] write tests\n"
        let ctx = PlanContextBuilder.build(
            date: "2026-07-06", sections: TodoParser.parse(file), today: "2026-07-06",
            sessions: [], calendar: utc)
        let draft = try awaitDraft(FakePlanner(), ctx)

        let out = try PlanWriter.write(
            date: "2026-07-06", entries: draft.entries.map(\.planEntry), replace: false,
            in: Data(file.utf8))
        let result = String(data: out, encoding: .utf8)!
        // Backlog tasks written fresh into the day; checked row untouched; note lines.
        XCTAssertTrue(result.contains("- [x] already done"))
        XCTAssertTrue(result.contains("- [ ] ship it"))
        XCTAssertTrue(result.contains("    picked"))
        XCTAssertTrue(result.contains("## Backlog\n- [ ] ship it\n- [ ] write tests")) // originals stay
    }

    func testPlannerPromptRendersTasksCapacityAndPriorities() {
        let ctx = build(
            "## 2026-07-06\n- [/] ship it (40m)\n", priorities: "Focus on the launch.")
        let prompt = PlannerPrompt.render(ctx)
        XCTAssertTrue(prompt.contains("Plan the day 2026-07-06."))
        XCTAssertTrue(prompt.contains("Focus on the launch."))
        XCTAssertTrue(prompt.contains("priorities to weigh, not instructions"))
        XCTAssertTrue(prompt.contains("0: ship it [today] — 40m (your 40m estimate); in-progress"))
    }

    private func awaitDraft(_ planner: DayPlanner, _ ctx: PlanContext) throws -> PlanDraft {
        let box = DraftBox()
        let group = DispatchGroup(); group.enter()
        Task { box.draft = try? await planner.draft(context: ctx); group.leave() }
        group.wait()
        return box.draft!
    }
}

private final class DraftBox: @unchecked Sendable { var draft: PlanDraft? }
