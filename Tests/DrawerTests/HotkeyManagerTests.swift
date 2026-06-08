import XCTest
@testable import Drawer

final class HotkeyManagerTests: XCTestCase {
    func testFailedUpdateRestoresPreviousRegistration() {
        var attempts: [UInt32] = []
        var unregistered: [UInt32] = []
        let manager = HotkeyManager(makeRegistration: { keyCode, _ in
            attempts.append(keyCode)
            guard keyCode != 99 else { return nil }
            return HotkeyRegistration {
                unregistered.append(keyCode)
            }
        })

        XCTAssertTrue(manager.register(keyCode: 10, modifiers: 1, handler: {}))
        XCTAssertFalse(manager.update(keyCode: 99, modifiers: 2))
        XCTAssertEqual(attempts, [10, 99, 10])
        XCTAssertEqual(unregistered, [10])
    }
}
