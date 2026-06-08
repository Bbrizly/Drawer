import AppKit
@testable import Drawer
import DrawerCore
import SwiftUI
import XCTest

@MainActor
final class DrawerVisualRenderTests: XCTestCase {
    func testRenderDrawerWhenRequested() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["DRAWER_RENDER_DIR"] else {
            throw XCTSkip("Set DRAWER_RENDER_DIR to generate visual review images.")
        }

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
                DrawerView(store: store, timer: timer),
                appearance: .aqua,
                size: size,
                to: outputURL.appendingPathComponent("drawer-\(name)-light.png")
            )
            try render(
                DrawerView(store: store, timer: timer),
                appearance: .darkAqua,
                size: size,
                to: outputURL.appendingPathComponent("drawer-\(name)-dark.png")
            )
        }
        UserDefaults.standard.set(DrawerTheme.liquidGlass.rawValue, forKey: "drawerTheme")
        timer.start(taskTitle: "Focus", seconds: 25 * 60)
        try render(
            DrawerView(store: store, timer: timer),
            appearance: .darkAqua,
            size: size,
            to: outputURL.appendingPathComponent("drawer-glass-active-dark.png")
        )
        timer.reset()
        UserDefaults.standard.removeObject(forKey: "drawerTheme")
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
}
