import XCTest

@testable import Drawer

/// The lot chunks its own rows instead of letting an adaptive grid do it, so
/// this arithmetic is the layout. A grid that worked the column count out for
/// itself had to ask the scroll view how much room was left, which is the very
/// thing the answer decides, and the app locked up mid-scroll.
final class LotGridTests: XCTestCase {
    private let cardWidth: CGFloat = 196
    private let gutter: CGFloat = 8
    private let edgePad: CGFloat = 14

    private func columns(_ width: CGFloat) -> Int {
        ParkingLotView.columns(
            width: width, cardWidth: cardWidth, gutter: gutter, edgePad: edgePad)
    }

    func testCardsPlusGuttersFitTheWidth() {
        // Three cards and the two gutters between them, plus both edges.
        let exact = cardWidth * 3 + gutter * 2 + edgePad * 2
        XCTAssertEqual(columns(exact), 3)
        // One point short of a fourth card is still three.
        XCTAssertEqual(columns(exact + cardWidth + gutter - 1), 3)
        XCTAssertEqual(columns(exact + cardWidth + gutter), 4)
    }

    func testNarrowPanelStillGetsOneColumn() {
        XCTAssertEqual(columns(40), 1)
        XCTAssertEqual(columns(0), 1)
        XCTAssertEqual(columns(-100), 1)
    }

    func testRowsCoverEveryCardInOrder() {
        let rows = ParkingLotView.rows(count: 7, columns: 3)
        XCTAssertEqual(rows, [[0, 1, 2], [3, 4, 5], [6]])
        XCTAssertEqual(rows.flatMap { $0 }, Array(0..<7))
    }

    func testRowsHandleEmptyAndExactFits() {
        XCTAssertEqual(ParkingLotView.rows(count: 0, columns: 3), [])
        XCTAssertEqual(ParkingLotView.rows(count: 6, columns: 3), [[0, 1, 2], [3, 4, 5]])
        XCTAssertEqual(ParkingLotView.rows(count: 2, columns: 5), [[0, 1]])
    }

    /// A zero column count would divide by zero in the stride.
    func testRowsSurviveAZeroColumnCount() {
        XCTAssertEqual(ParkingLotView.rows(count: 3, columns: 0), [[0], [1], [2]])
    }

    /// Rows are keyed on their first card, so every row must have one.
    func testEveryRowHasAFirstCardToKeyOn() {
        for count in 0...20 {
            for cols in 1...5 {
                let rows = ParkingLotView.rows(count: count, columns: cols)
                XCTAssertTrue(rows.allSatisfy { !$0.isEmpty }, "\(count) in \(cols)")
                XCTAssertEqual(Set(rows.map(\.first)).count, rows.count, "\(count) in \(cols)")
            }
        }
    }
}
