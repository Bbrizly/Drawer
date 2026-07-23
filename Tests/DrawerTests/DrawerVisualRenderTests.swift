import AppKit
@testable import Drawer
import DrawerCore
import SwiftUI
import XCTest

@MainActor
final class DrawerVisualRenderTests: XCTestCase {
    func testIdlePomodoroTimerPillStaysCompactForHeaderRow() throws {
        let timer = PomodoroTimer()

        let width = fittingWidth(PomodoroHeaderView(timer: timer))

        XCTAssertLessThanOrEqual(
            width,
            190,
            "Idle Pomodoro timer should fit the standard drawer timer row without widening the panel."
        )
    }

    func testRunningFocusTimerPillStaysCompactForWorkTimerRow() throws {
        let timer = FocusTimer()
        timer.start(taskTitle: "Focus", seconds: 25 * 60)

        let width = fittingWidth(TimerHeaderView(timer: timer))

        XCTAssertLessThanOrEqual(
            width,
            155,
            "Running focus timer should stay compact enough to sit beside the work timer in the standard drawer content width."
        )
    }

    func testNotebookHeaderChromeStaysRightOfMarginRule() throws {
        FontLoader.registerBundledFonts()

        let sampleFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawer-notebook-margin-\(UUID().uuidString).md")
        try """
        ## 2026-06-07
        - [ ] Finish the product walkthrough (15m)
        """.write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        let store = TodoStore(fileURL: sampleFile, todayProvider: { "2026-06-07" })
        store.reload()
        let timer = FocusTimer()
        let pomodoroTimer = PomodoroTimer()
        let workLog = WorkSessionLog(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("drawer-notebook-margin-\(UUID().uuidString).jsonl"))
        let workClock = WorkClock(log: workLog)

        UserDefaults.standard.set(DrawerTheme.notebook.rawValue, forKey: "drawerTheme")
        defer { UserDefaults.standard.removeObject(forKey: "drawerTheme") }

        let bitmap = try renderBitmap(
            DrawerView(
                store: store,
                timer: timer,
                pomodoroTimer: pomodoroTimer,
                workClock: workClock
            ),
            appearance: .aqua,
            size: NSSize(width: 320, height: 220)
        )

        XCTAssertFalse(
            containsDarkChromePixels(
                in: bitmap,
                xRange: 32..<38,
                yRange: 45..<min(170, bitmap.pixelsHigh)
            ),
            "Notebook header chrome should not draw in the paper gutter before the red rule."
        )
    }

    func testRenderDrawerWhenRequested() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["DRAWER_RENDER_DIR"] else {
            throw XCTSkip("Set DRAWER_RENDER_DIR to generate visual review images.")
        }
        FontLoader.registerBundledFonts() // so the Pixel theme renders in its real face

        let sampleFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("drawer-visual-\(UUID().uuidString).md")
        let sample = """
        ## 2026-06-07
        - [ ] Finish the product walkthrough (15m)
        - [ ] Reply to the design feedback
        - [x] Review the launch checklist
        ## 2026-06-06
        - [ ] Send the follow-up notes (10m)
        ## 2026-06-08
        - [ ] Prepare tomorrow's priorities (30m)
        ## Backlog
        - [ ] Explore keyboard-first task capture
        ## Archive
        ### Games
        - [ ] Parked roguelike prototype
        """
        try sample.write(to: sampleFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        let store = TodoStore(fileURL: sampleFile, todayProvider: { "2026-06-07" })
        store.reload()
        let timer = FocusTimer()
        let pomodoroTimer = PomodoroTimer()
        let workLog = WorkSessionLog(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("drawer-visual-work-\(UUID().uuidString).jsonl"))
        let workClock = WorkClock(log: workLog)

        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        let size = NSSize(width: 320, height: 600)
        // DrawerView reads its theme from @AppStorage("drawerTheme"), so drive
        // it through UserDefaults rather than the environment (DrawerView
        // re-injects its own theme, which would override an outer .environment).
        for theme in DrawerTheme.allCases {
            let name = theme.rawValue
            UserDefaults.standard.set(theme.rawValue, forKey: "drawerTheme")
            try render(
                DrawerView(
                    store: store,
                    timer: timer,
                    pomodoroTimer: pomodoroTimer,
                    workClock: workClock
                ),
                appearance: .aqua,
                size: size,
                to: outputURL.appendingPathComponent("drawer-\(name)-light.png")
            )
            try render(
                DrawerView(
                    store: store,
                    timer: timer,
                    pomodoroTimer: pomodoroTimer,
                    workClock: workClock
                ),
                appearance: .darkAqua,
                size: size,
                to: outputURL.appendingPathComponent("drawer-\(name)-dark.png")
            )
        }
        UserDefaults.standard.set(DrawerTheme.liquidGlass.rawValue, forKey: "drawerTheme")
        timer.start(taskTitle: "Focus", seconds: 25 * 60)
        try render(
            DrawerView(
                store: store,
                timer: timer,
                pomodoroTimer: pomodoroTimer,
                workClock: workClock
            ),
            appearance: .darkAqua,
            size: size,
            to: outputURL.appendingPathComponent("drawer-glass-active-dark.png")
        )
        timer.reset()
        UserDefaults.standard.removeObject(forKey: "drawerTheme")
    }

    func testRenderSettingsWhenRequested() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["DRAWER_SETTINGS_RENDER_DIR"] else {
            throw XCTSkip("Set DRAWER_SETTINGS_RENDER_DIR to generate the settings visual review image.")
        }

        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )

        UserDefaults.standard.set(DrawerTheme.liquidGlass.rawValue, forKey: "drawerTheme")
        defer { UserDefaults.standard.removeObject(forKey: "drawerTheme") }

        try renderSettings(
            appearance: .darkAqua,
            size: NSSize(width: 440, height: 580),
            scrollOffset: 0,
            to: outputURL.appendingPathComponent("settings-general-dark.png")
        )
        try renderSettings(
            appearance: .darkAqua,
            size: NSSize(width: 440, height: 580),
            scrollOffset: 1420,
            to: outputURL.appendingPathComponent("settings-timers-dark.png")
        )

        UserDefaults.standard.set(DrawerTheme.pixel.rawValue, forKey: "drawerTheme")
        try renderSettings(
            appearance: .darkAqua,
            size: NSSize(width: 440, height: 580),
            scrollOffset: 1420,
            to: outputURL.appendingPathComponent("settings-timers-pixel-dark.png")
        )
    }

    func testSettingsPageWearsTheThemeSurface() throws {
        // Dark appearance on purpose: the picked theme decides the chrome, not
        // the OS setting, so Notebook settings stay on warm paper either way.
        UserDefaults.standard.set(DrawerTheme.notebook.rawValue, forKey: "drawerTheme")
        let paper = try renderSettingsBitmap(
            appearance: .darkAqua,
            size: NSSize(width: 440, height: 580),
            scrollOffset: 0
        )
        // Below the tab strip and its divider, the left gutter is nothing but page.
        for y in stride(from: 250, to: paper.pixelsHigh, by: 60) {
            guard let color = paper.colorAt(x: 8, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            XCTAssertGreaterThan(
                color.redComponent, 0.9,
                "The Notebook settings page should be paper, not a dark or system surface."
            )
            XCTAssertGreaterThan(
                color.redComponent, color.blueComponent,
                "Notebook paper is warm, so red should lead blue."
            )
        }

        UserDefaults.standard.set(DrawerTheme.pixel.rawValue, forKey: "drawerTheme")
        defer { UserDefaults.standard.removeObject(forKey: "drawerTheme") }
        let board = try renderSettingsBitmap(
            appearance: .aqua,
            size: NSSize(width: 440, height: 580),
            scrollOffset: 0
        )
        for y in stride(from: 250, to: board.pixelsHigh, by: 60) {
            guard let color = board.colorAt(x: 8, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            XCTAssertLessThan(
                color.redComponent, 0.3,
                "The Pixel settings page should be the dark arcade surface, whatever the OS is set to."
            )
        }
    }

    private func containsDarkChromePixels(
        in bitmap: NSBitmapImageRep,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Bool {
        for y in yRange {
            for x in xRange {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.05 else {
                    continue
                }
                if isDarkChromeInk(color) {
                    return true
                }
            }
        }
        return false
    }

    private func isDarkChromeInk(_ color: NSColor) -> Bool {
        color.redComponent < 0.72
            && color.greenComponent < 0.72
            && color.blueComponent < 0.72
    }

    /// Renders the drawer over a colorful gradient. Glass and material plates
    /// sample what is behind the panel, so a clear window would show nothing;
    /// the gradient stands in for a desktop wallpaper.
    private func render<V: View>(
        _ view: V,
        appearance: NSAppearance.Name,
        size: NSSize,
        to outputURL: URL
    ) throws {
        let backdrop = NSHostingView(rootView:
            LinearGradient(
                colors: [.blue, .purple, .pink, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(view.padding(14))
        )
        backdrop.frame = NSRect(origin: .zero, size: size)
        backdrop.appearance = NSAppearance(named: appearance)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = backdrop
        window.layoutIfNeeded()
        backdrop.layoutSubtreeIfNeeded()

        guard let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)
        else {
            XCTFail("Could not create a bitmap for the drawer.")
            return
        }
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode the drawer PNG.")
            return
        }
        try png.write(to: outputURL)
    }

    private func renderBitmap<V: View>(
        _ view: V,
        appearance: NSAppearance.Name,
        size: NSSize
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)

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
            XCTFail("Could not create a bitmap for the drawer.")
            throw CocoaError(.fileReadUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func renderSettings(
        appearance: NSAppearance.Name,
        size: NSSize,
        scrollOffset: CGFloat,
        to outputURL: URL
    ) throws {
        let host = NSHostingView(rootView:
            SettingsView(
                onChooseFile: { _ in },
                onHotkeyChange: { _ in true },
                onLayoutChange: {},
                onRightCommandTapChange: { _ in }
            )
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)

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

        if scrollOffset > 0, let scrollView = firstScrollView(in: host) {
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let visibleHeight = scrollView.contentView.bounds.height
            let y = min(scrollOffset, max(0, documentHeight - visibleHeight))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
        }

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not create a bitmap for the settings window.")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode the settings PNG.")
            return
        }
        try png.write(to: outputURL)
    }

    private func renderSettingsBitmap(
        appearance: NSAppearance.Name,
        size: NSSize,
        scrollOffset: CGFloat
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView:
            SettingsView(
                onChooseFile: { _ in },
                onHotkeyChange: { _ in true },
                onLayoutChange: {},
                onRightCommandTapChange: { _ in }
            )
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: appearance)

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

        if scrollOffset > 0, let scrollView = firstScrollView(in: host) {
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let visibleHeight = scrollView.contentView.bounds.height
            let y = min(scrollOffset, max(0, documentHeight - visibleHeight))
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
        }

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not create a bitmap for the settings window.")
            throw CocoaError(.fileReadUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func fittingWidth<V: View>(_ view: V) -> CGFloat {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.width
    }
}
