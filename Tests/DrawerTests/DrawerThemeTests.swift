import AppKit
@testable import Drawer
import SwiftUI
import XCTest

final class DrawerThemeTests: XCTestCase {
    func testRawValueRoundTrip() {
        for theme in DrawerTheme.allCases {
            XCTAssertEqual(DrawerTheme(rawValue: theme.rawValue), theme)
        }
    }

    func testDefaultIsLiquidGlass() {
        XCTAssertEqual(DrawerTheme.default, .liquidGlass)
    }

    func testTokensAreSane() {
        for theme in DrawerTheme.allCases {
            if theme == .windowsXP {
                XCTAssertEqual(theme.panelCornerRadius, 0)
            } else {
                XCTAssertGreaterThan(theme.panelCornerRadius, 0)
            }
            XCTAssertGreaterThanOrEqual(theme.checkboxSize, 13)
            XCTAssertLessThanOrEqual(theme.checkboxSize, 24)
            XCTAssertGreaterThanOrEqual(theme.rowVerticalPadding, 0)
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }

    func testEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.drawerTheme, .liquidGlass)
    }

    func testArtDirectedThemesExist() {
        for theme in [DrawerTheme.medieval, .pixel, .artistic, .notebook, .windowsXP] {
            XCTAssertTrue(theme.isArtDirected)
            XCTAssertNotNil(theme.sectionHeaderStyle)
        }
    }

    func testPixelUsesSquareCheckboxes() {
        XCTAssertEqual(DrawerTheme.pixel.checkboxSymbol(done: false, inProgress: false), "square")
        XCTAssertEqual(DrawerTheme.pixel.checkboxSymbol(done: true, inProgress: false), "checkmark.square.fill")
        XCTAssertEqual(DrawerTheme.windowsXP.checkboxSymbol(done: false, inProgress: false), "square")
        XCTAssertEqual(DrawerTheme.windowsXP.checkboxSymbol(done: true, inProgress: false), "checkmark.square.fill")
        // The round themes keep circles.
        XCTAssertEqual(DrawerTheme.medieval.checkboxSymbol(done: false, inProgress: false), "circle")
    }

    func testWindowsXPForcesLightChrome() {
        XCTAssertEqual(DrawerTheme.windowsXP.displayName, "Windows XP")
        XCTAssertEqual(DrawerTheme.windowsXP.forcedColorScheme, .light)
        XCTAssertEqual(DrawerTheme.windowsXP.popoverColorScheme, .light)
        XCTAssertTrue(DrawerTheme.windowsXP.usesXPChrome)
        XCTAssertEqual(DrawerTheme.windowsXP.rowCornerRadius, 0)
    }

    func testWindowsXPFontFallbackRegisters() {
        FontLoader.registerBundledFonts()
        _ = FontLoader.xpFont(size: 11)
        // Arial is the macOS fallback when Tahoma is not installed.
        XCTAssertTrue(
            FontLoader.xpFontIsAvailable()
                || NSFontManager.shared.availableFontFamilies.contains("Arial")
        )
    }

    func testBundledPixelFontRegisters() {
        FontLoader.registerBundledFonts()
        XCTAssertTrue(
            NSFontManager.shared.availableFontFamilies.contains(FontLoader.pixelFamily),
            "The Pixelify Sans face should register from the resource bundle."
        )
    }
}
