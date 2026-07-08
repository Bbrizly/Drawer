import AppKit
@testable import Drawer
import DrawerCore
import SwiftUI
import XCTest

/// Smoke coverage for the companion pane: the router's tiny state machine and
/// that each wired pane (Plan, Work) renders with a real controller attached.
/// Before these, DrawerVisualRenderTests only ever built DrawerView with nil
/// controllers, so the pane content paths never executed in CI.
@MainActor
final class CompanionPaneRenderTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pane-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: PaneRouter

    func testRouterToggleReopensLastSection() {
        let router = PaneRouter()
        XCTAssertNil(router.activePane)
        router.toggleOpen()
        XCTAssertEqual(router.activePane, .plan) // default lastOpened
        router.show(.work)
        XCTAssertEqual(router.activePane, .work)
        router.toggleOpen()
        XCTAssertNil(router.activePane) // closes
        router.toggleOpen()
        XCTAssertEqual(router.activePane, .work) // reopens to last section
    }

    // MARK: pane render smoke

    func testWorkPaneRendersWithLiveController() throws {
        let controller = makeAttributionController()
        let bitmap = try renderBitmap(
            CompanionPaneView(pane: .work, router: PaneRouter(), attribution: controller))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
    }

    func testPlanPaneRendersWithLiveController() throws {
        let controller = makePlannerController()
        let bitmap = try renderBitmap(
            CompanionPaneView(pane: .plan, router: PaneRouter(), planner: controller))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
    }

    // MARK: helpers

    private func makeAttributionController() -> AttributionController {
        let workLog = WorkSessionLog(fileURL: dir.appendingPathComponent("work.jsonl"))
        return AttributionController(
            raw: RawActivityStore(fileURL: dir.appendingPathComponent("raw.jsonl")),
            service: AttributionService(
                queue: AttributionQueueStore(fileURL: dir.appendingPathComponent("queue.jsonl")),
                log: workLog),
            workLog: workLog,
            daySummaries: DaySummaryStore(fileURL: dir.appendingPathComponent("days.jsonl")),
            rulesURL: dir.appendingPathComponent("rules.json"),
            candidatesProvider: { [TaskCandidate(id: "t1", title: "Ship it", priority: true)] },
            manualSpansProvider: { _ in [] },
            todayProvider: { "2026-07-06" })
    }

    private func makePlannerController() -> PlannerController {
        let file = dir.appendingPathComponent("Drawer.md")
        try? "## 2026-07-06\n- [ ] a task\n".write(to: file, atomically: true, encoding: .utf8)
        let store = TodoStore(fileURL: file, todayProvider: { "2026-07-06" })
        store.reload()
        return PlannerController(
            store: store,
            workLog: WorkSessionLog(fileURL: dir.appendingPathComponent("work.jsonl")),
            scheduleStore: DayScheduleStore(fileURL: dir.appendingPathComponent("schedules.jsonl")),
            todayProvider: { "2026-07-06" },
            prioritiesProvider: { (nil, false) })
    }

    private func renderBitmap<V: View>(_ view: V) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 500)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw XCTSkip("bitmap caching unavailable in this environment")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
