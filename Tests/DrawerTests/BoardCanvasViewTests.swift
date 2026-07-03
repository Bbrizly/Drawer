import AppKit
@testable import Drawer
import QuartzCore
import XCTest

@MainActor
final class BoardCanvasViewTests: XCTestCase {
    func testTransparentBackgroundHidesPaperRulesEvenWhenPaperIsEnabled() {
        let view = BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))

        view.setPaper(true)
        XCTAssertFalse(paperLayer(in: view).isHidden)

        view.setTransparent(true)
        XCTAssertTrue(
            paperLayer(in: view).isHidden,
            "Transparent canvas mode should suppress notebook rule lines, even when paper mode is also enabled."
        )
    }

    private func paperLayer(
        in view: BoardCanvasView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CALayer {
        guard let contentLayer = view.layer?.sublayers?.first(where: { layer in
            layer.sublayers?.contains(where: { $0.zPosition == -1_000_000 }) == true
        }),
              let paperLayer = contentLayer.sublayers?.first(where: { $0.zPosition == -1_000_000 })
        else {
            XCTFail("Expected the canvas to install a paper rule layer.", file: file, line: line)
            return CALayer()
        }

        return paperLayer
    }
}
