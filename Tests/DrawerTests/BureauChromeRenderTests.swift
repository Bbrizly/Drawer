import AppKit
@testable import Drawer
import DrawerBureau
import DrawerCore
import SwiftUI
import XCTest

/// Chrome-only render coverage for the Bureau integration. It mounts DrawerView
/// with the flag on and the facade wired, in list mode (Bureau mode not
/// entered), so no live `SKScene` frame is asserted: only the SwiftUI chrome
/// (mode button, queue chip, row wiring) is exercised. A live scene frame is
/// left unasserted on purpose, per the impl spec's test plan.
@MainActor
final class BureauChromeRenderTests: XCTestCase {
    func testDrawerRendersWithBureauFlagOnAndAQueuedTask() throws {
        FontLoader.registerBundledFonts()

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("Drawer.md")
        try """
        ## 2026-07-13
        - [ ] Finish the product walkthrough (15m)
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let store = TodoStore(fileURL: fileURL, todayProvider: { "2026-07-13" })
        store.reload()
        let feature = BureauFeature(store: store, directory: dir)
        if let item = store.todayItems.first { feature.queue(item) }
        XCTAssertEqual(feature.queuedCount, 1)

        UserDefaults.standard.set(true, forKey: "feature.bureau")
        defer { UserDefaults.standard.removeObject(forKey: "feature.bureau") }

        var view = DrawerView(
            store: store,
            timer: FocusTimer(),
            pomodoroTimer: PomodoroTimer(),
            workClock: WorkClock(log: WorkSessionLog(fileURL: dir.appendingPathComponent("work.jsonl")))
        )
        view.bureau = feature

        let bitmap = try renderBitmap(view, size: NSSize(width: 320, height: 320))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
    }

    /// With the flag off the drawer must render exactly as today (byte-identical
    /// behavior): the facade is wired but the branch never lights up.
    func testDrawerRendersUnchangedWithBureauFlagOff() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("Drawer.md")
        try "## 2026-07-13\n- [ ] Reply to the design feedback\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let store = TodoStore(fileURL: fileURL, todayProvider: { "2026-07-13" })
        store.reload()

        UserDefaults.standard.set(false, forKey: "feature.bureau")
        defer { UserDefaults.standard.removeObject(forKey: "feature.bureau") }

        var view = DrawerView(
            store: store,
            timer: FocusTimer(),
            pomodoroTimer: PomodoroTimer(),
            workClock: WorkClock(log: WorkSessionLog(fileURL: dir.appendingPathComponent("work.jsonl")))
        )
        view.bureau = BureauFeature(store: store, directory: dir)

        let bitmap = try renderBitmap(view, size: NSSize(width: 320, height: 320))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
    }

    private func renderBitmap<V: View>(_ view: V, size: NSSize) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileReadUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
