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
            XCTAssertGreaterThan(theme.panelCornerRadius, 0)
            XCTAssertGreaterThanOrEqual(theme.checkboxSize, 14)
            XCTAssertLessThanOrEqual(theme.checkboxSize, 24)
            XCTAssertGreaterThanOrEqual(theme.rowVerticalPadding, 0)
            XCTAssertFalse(theme.displayName.isEmpty)
        }
    }

    func testEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.drawerTheme, .liquidGlass)
    }

    func testThreeNewThemesExist() {
        for theme in [DrawerTheme.medieval, .pixel, .artistic] {
            XCTAssertTrue(theme.isArtDirected)
            XCTAssertNotNil(theme.sectionHeaderStyle)
        }
    }

    func testPixelUsesSquareCheckboxes() {
        XCTAssertEqual(DrawerTheme.pixel.checkboxSymbol(done: false, inProgress: false), "square")
        XCTAssertEqual(DrawerTheme.pixel.checkboxSymbol(done: true, inProgress: false), "checkmark.square.fill")
        // The round themes keep circles.
        XCTAssertEqual(DrawerTheme.medieval.checkboxSymbol(done: false, inProgress: false), "circle")
    }

    func testBundledPixelFontRegisters() {
        FontLoader.registerBundledFonts()
        XCTAssertTrue(
            NSFontManager.shared.availableFontFamilies.contains(FontLoader.pixelFamily),
            "The Pixelify Sans face should register from the resource bundle."
        )
    }
}
