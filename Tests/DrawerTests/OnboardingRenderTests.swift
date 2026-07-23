import AppKit
@testable import Drawer
import SwiftUI
import XCTest

/// Visual review for the chrome windows: the four walkthrough steps and the
/// Settings tabs, in whatever theme is picked. Same deal as the drawer render
/// test: it only writes files when you ask for them.
@MainActor
final class OnboardingRenderTests: XCTestCase {
    func testRenderOnboardingWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["DRAWER_ONBOARDING_RENDER_DIR"] else {
            throw XCTSkip("Set DRAWER_ONBOARDING_RENDER_DIR to generate walkthrough review images.")
        }
        FontLoader.registerBundledFonts()
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let themes = ProcessInfo.processInfo.environment["DRAWER_ONBOARDING_THEMES"]?
            .split(separator: ",").compactMap { DrawerTheme(rawValue: String($0)) }
            ?? [.notebook]

        for theme in themes {
            UserDefaults.standard.set(theme.rawValue, forKey: "drawerTheme")
            for step in 0...3 {
                try render(
                    OnboardingView(startStep: step) {},
                    size: NSSize(width: 620, height: 580),
                    to: out.appendingPathComponent("onboarding-\(theme.rawValue)-\(step).png")
                )
            }
            try render(
                SettingsView(
                    onChooseFile: { _ in },
                    onHotkeyChange: { _ in true },
                    onLayoutChange: {},
                    onRightCommandTapChange: { _ in }
                ),
                size: NSSize(width: 540, height: 580),
                to: out.appendingPathComponent("settings-\(theme.rawValue).png")
            )
        }
        UserDefaults.standard.removeObject(forKey: "drawerTheme")
    }

    private func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        // The theme pins the window appearance one runloop turn later.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not create a bitmap.")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode the PNG.")
            return
        }
        try png.write(to: url)
    }
}
