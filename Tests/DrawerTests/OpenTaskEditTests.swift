@testable import Drawer
import XCTest

/// The slot that lets quitting write through a title or note the user never
/// submitted.
@MainActor
final class OpenTaskEditTests: XCTestCase {
    override func setUp() async throws {
        OpenTaskEdit.shared.release()
    }

    func testCommitRunsTheClaimedSaveOnce() {
        var saves = 0
        OpenTaskEdit.shared.claim { saves += 1 }

        OpenTaskEdit.shared.commit()
        OpenTaskEdit.shared.commit()

        XCTAssertEqual(saves, 1, "the open edit was written twice")
    }

    func testCommitWithNothingOpenDoesNothing() {
        OpenTaskEdit.shared.commit()  // must not trap
    }

    /// The field saved itself the normal way, so quitting has nothing to do.
    func testAReleasedEditIsNotCommittedAgain() {
        var saves = 0
        OpenTaskEdit.shared.claim { saves += 1 }
        OpenTaskEdit.shared.release()

        OpenTaskEdit.shared.commit()

        XCTAssertEqual(saves, 0, "an already saved edit was written a second time")
    }

    /// Opening a second field replaces the first. Only one field can hold focus,
    /// so a leftover claim would write a draft the user had already left.
    func testASecondClaimReplacesTheFirst() {
        var first = 0
        var second = 0
        OpenTaskEdit.shared.claim { first += 1 }
        OpenTaskEdit.shared.claim { second += 1 }

        OpenTaskEdit.shared.commit()

        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
    }
}
