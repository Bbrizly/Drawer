import XCTest
@testable import Drawer

final class PanelTransitionStateTests: XCTestCase {
    func testStaleHideCompletionCannotOrderOutReshownPanel() {
        var state = PanelTransitionState()
        state.beginShow()
        let hideGeneration = state.beginHide()
        state.beginShow()

        XCTAssertFalse(state.shouldOrderOut(hideGeneration: hideGeneration))
        XCTAssertTrue(state.isShown)
    }
}
