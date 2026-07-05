import XCTest
@testable import DrawerCore

final class DrawerFilePathTests: XCTestCase {
    func testFileArgumentWinsOverAll() {
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp", "--file", "/tmp/a.md"],
            environment: ["DRAWER_FILE": "/tmp/env.md"],
            storedDefault: "/tmp/stored.md"
        )
        XCTAssertEqual(path, "/tmp/a.md")
    }

    func testEnvironmentUsedWhenNoFileArgument() {
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp"],
            environment: ["DRAWER_FILE": "/tmp/env.md"],
            storedDefault: "/tmp/stored.md"
        )
        XCTAssertEqual(path, "/tmp/env.md")
    }

    func testStoredDefaultUsedWhenNoArgumentOrEnvironment() {
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp"],
            environment: [:],
            storedDefault: "/tmp/stored.md"
        )
        XCTAssertEqual(path, "/tmp/stored.md")
    }

    func testFallsBackToDefaultWhenNothingSet() {
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp"],
            environment: [:],
            storedDefault: nil
        )
        XCTAssertEqual(path, DrawerFilePath.default)
    }

    func testEmptyEnvironmentAndStoredAreSkipped() {
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp"],
            environment: ["DRAWER_FILE": ""],
            storedDefault: ""
        )
        XCTAssertEqual(path, DrawerFilePath.default)
    }

    func testEmptyFileArgumentValueIsSkipped() {
        // "--file ''" must not shadow the stored default with an empty path,
        // matching how empty env/stored values fall through.
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp", "--file", ""],
            environment: [:],
            storedDefault: "/tmp/stored.md"
        )
        XCTAssertEqual(path, "/tmp/stored.md")
    }

    func testFileArgumentWithoutValueIsIgnored() {
        // "--file" as the last token has no path after it; fall through.
        let path = DrawerFilePath.resolve(
            arguments: ["drawer-mcp", "--file"],
            environment: [:],
            storedDefault: "/tmp/stored.md"
        )
        XCTAssertEqual(path, "/tmp/stored.md")
    }
}
