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
}
