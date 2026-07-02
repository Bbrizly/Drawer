import CoreGraphics
import XCTest
@testable import DrawerCore

final class BoardGeometryTests: XCTestCase {
    func testToBoardAndToViewAreInverses() {
        let v = BoardViewport(x: 30, y: -20, zoom: 1.5)
        let p = CGPoint(x: 123, y: 45)
        let board = BoardGeometry.toBoard(p, viewport: v)
        let back = BoardGeometry.toView(board, viewport: v)
        XCTAssertEqual(back.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.0001)
    }

    func testHitTestReturnsTopmostByZ() {
        let a = BoardItem(kind: .text, x: 0, y: 0, width: 100, height: 100, z: 1)
        let b = BoardItem(kind: .text, x: 10, y: 10, width: 100, height: 100, z: 5)
        let hit = BoardGeometry.hitTest(CGPoint(x: 20, y: 20), items: [a, b])
        XCTAssertEqual(hit, b.id)
    }

    func testHitTestOverEmptySpaceIsNil() {
        let a = BoardItem(kind: .text, x: 0, y: 0, width: 10, height: 10, z: 1)
        XCTAssertNil(BoardGeometry.hitTest(CGPoint(x: 500, y: 500), items: [a]))
    }
}
