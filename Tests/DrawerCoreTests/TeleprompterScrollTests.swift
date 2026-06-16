import XCTest
@testable import DrawerCore

final class TeleprompterScrollTests: XCTestCase {
    func testTickAdvancesBySpeedTimesDelta() {
        var scroll = TeleprompterScroll(speed: 40)
        scroll.contentHeight = 1000
        scroll.viewportHeight = 200
        scroll.tick(0.5)
        XCTAssertEqual(scroll.offset, 20, accuracy: 0.0001)
    }

    func testTickClampsAtMaxOffset() {
        var scroll = TeleprompterScroll(speed: 100)
        scroll.contentHeight = 300
        scroll.viewportHeight = 200 // maxOffset = 100
        scroll.tick(5) // would be 500
        XCTAssertEqual(scroll.offset, 100, accuracy: 0.0001)
        XCTAssertTrue(scroll.atEnd)
    }

    func testMaxOffsetZeroWhenContentFitsViewport() {
        var scroll = TeleprompterScroll(speed: 50)
        scroll.contentHeight = 100
        scroll.viewportHeight = 400
        XCTAssertEqual(scroll.maxOffset, 0)
        scroll.tick(1)
        XCTAssertEqual(scroll.offset, 0)
        XCTAssertTrue(scroll.atEnd)
    }

    func testRestartResetsOffset() {
        var scroll = TeleprompterScroll(speed: 50)
        scroll.contentHeight = 1000
        scroll.viewportHeight = 200
        scroll.tick(2)
        XCTAssertGreaterThan(scroll.offset, 0)
        scroll.restart()
        XCTAssertEqual(scroll.offset, 0)
    }

    func testNegativeOrZeroDeltaDoesNothing() {
        var scroll = TeleprompterScroll(speed: 50)
        scroll.contentHeight = 1000
        scroll.viewportHeight = 200
        scroll.tick(0)
        scroll.tick(-1)
        XCTAssertEqual(scroll.offset, 0)
    }
}
