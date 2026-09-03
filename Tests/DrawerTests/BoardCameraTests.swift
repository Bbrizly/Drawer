import AppKit
@testable import Drawer
import DrawerCore
import XCTest

/// Who owns the board camera. The canvas drives it during a gesture and the
/// store owns it the rest of the time; the bug being pinned here is a SwiftUI
/// re-render for an unrelated change pushing the last persisted viewport back
/// over a live pan.
@MainActor
final class BoardCameraTests: XCTestCase {
    private func makeView() -> BoardCanvasView {
        BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    func testStaleStoreViewportDoesNotOverwriteALivePan() {
        let view = makeView()
        let persisted = BoardViewport(x: 0, y: 0, zoom: 1)
        view.setViewportFromStore(persisted, revision: 0)

        view.panBy(40, 0)
        let panned = view.currentViewport

        // The store has not seen the pan yet; SwiftUI re-renders for an
        // unrelated item or theme change and hands back the old camera.
        view.setViewportFromStore(persisted, revision: 0)

        XCTAssertEqual(view.currentViewport, panned, "a stale store viewport snapped the board back")
    }

    func testEchoOfTheCommittedViewportReleasesOwnership() {
        let view = makeView()
        var committed: BoardViewport?
        view.onViewportCommit = { committed = $0 }
        view.setViewportFromStore(BoardViewport(), revision: 0)

        view.panBy(40, 0)
        view.flushViewport()
        let echo = try? XCTUnwrap(committed)
        XCTAssertEqual(echo, view.currentViewport)

        // The store publishes what the canvas just committed. That releases
        // ownership, so the next store value applies normally.
        view.setViewportFromStore(echo!, revision: 0)
        let programmatic = BoardViewport(x: 5, y: 6, zoom: 1.5)
        view.setViewportFromStore(programmatic, revision: 0)
        XCTAssertEqual(view.currentViewport, programmatic)
    }

    func testProgrammaticViewportWinsEvenMidGesture() {
        let view = makeView()
        view.setViewportFromStore(BoardViewport(), revision: 0)
        view.panBy(40, 0)

        // The zoom buttons bump the revision, which always overrides.
        let zoomed = BoardViewport(x: 10, y: 10, zoom: 2)
        view.setViewportFromStore(zoomed, revision: 1)

        XCTAssertEqual(view.currentViewport, zoomed)
    }

    func testSwitchingBoardsAppliesTheSelectedBoardViewport() {
        let store = BoardStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString), debounce: 0)
        store.applyViewport(BoardViewport(x: 1, y: 2, zoom: 1))
        let first = store.document.activeBoardID
        let second = store.addBoard()
        store.applyViewport(BoardViewport(x: 90, y: 90, zoom: 3))

        let view = makeView()
        view.setViewportFromStore(store.document.viewport, revision: store.viewportRevision)
        XCTAssertEqual(view.currentViewport, BoardViewport(x: 90, y: 90, zoom: 3))

        view.panBy(25, 0) // the canvas now owns the camera

        store.selectBoard(first)
        view.setViewportFromStore(store.document.viewport, revision: store.viewportRevision)
        XCTAssertEqual(view.currentViewport, BoardViewport(x: 1, y: 2, zoom: 1))
        XCTAssertEqual(store.document.activeBoardID, first)
        XCTAssertNotEqual(second.id, first)
    }

    func testRepeatedPansPublishOnceAfterTheQuietPeriod() {
        let view = makeView()
        var commits: [BoardViewport] = []
        view.onViewportCommit = { commits.append($0) }

        for _ in 0..<10 { view.panBy(4, 0) }
        XCTAssertEqual(commits.count, 0, "every pan event published a store change")

        let settled = expectation(description: "viewport commit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.last, view.currentViewport)
    }

    func testTeardownFlushesTheNewestViewport() {
        var commits: [BoardViewport] = []
        var expected = BoardViewport()
        do {
            let view = makeView()
            view.onViewportCommit = { commits.append($0) }
            view.panBy(12, 34)
            expected = view.currentViewport
            view.flushViewport()
        }
        XCTAssertEqual(commits.last, expected)
        XCTAssertNotEqual(expected, BoardViewport())
    }

    func testRecenterCommitsImmediately() {
        let view = makeView()
        var commits: [BoardViewport] = []
        view.onViewportCommit = { commits.append($0) }
        view.setItems([
            BoardItem(kind: .text, x: 1_000, y: 1_000, width: 100, height: 100, z: 1, title: "far"),
        ])

        view.recenter()

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.last, view.currentViewport)
        XCTAssertNotEqual(view.currentViewport, BoardViewport())

        // The commit is the canvas's own, so the store echoing it back must not
        // move the camera again.
        let after = view.currentViewport
        view.setViewportFromStore(after, revision: 0)
        XCTAssertEqual(view.currentViewport, after)
    }
}

/// One CALayer per item, reconfigured only when that item actually changed.
@MainActor
final class BoardDifferentialRenderTests: XCTestCase {
    private func item(_ title: String, x: Double = 0) -> BoardItem {
        BoardItem(kind: .text, x: x, y: 0, width: 100, height: 60, z: 1, title: title)
    }

    func testIdenticalItemsAreNotReconfigured() {
        let view = BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var configured: [UUID] = []
        view.onConfigureItem = { configured.append($0) }
        let items = [item("a"), item("b", x: 200)]

        view.setItems(items)
        XCTAssertEqual(configured.count, 2, "first pass builds both layers")

        configured.removeAll()
        view.setItems(items)
        XCTAssertEqual(configured, [], "unchanged items were reconfigured")
    }

    func testChangingOneItemReconfiguresOnlyThatItem() {
        let view = BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var items = [item("a"), item("b", x: 200)]
        view.setItems(items)

        var configured: [UUID] = []
        view.onConfigureItem = { configured.append($0) }
        items[1].title = "b changed"
        view.setItems(items)

        XCTAssertEqual(configured, [items[1].id])
    }

    func testRemovingOneItemDropsOnlyItsLayer() {
        let view = BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let items = [item("a"), item("b", x: 200)]
        view.setItems(items)
        XCTAssertEqual(view.renderedItemIDs, Set(items.map(\.id)))

        var configured: [UUID] = []
        view.onConfigureItem = { configured.append($0) }
        view.setItems([items[0]])

        XCTAssertEqual(view.renderedItemIDs, [items[0].id])
        XCTAssertEqual(configured, [], "the surviving item was reconfigured for a neighbour's removal")
    }
}

/// The appearance setters are called on every SwiftUI pass, so each one has to
/// be a no-op when the value has not moved.
@MainActor
final class BoardAppearanceTests: XCTestCase {
    private func makeView() -> BoardCanvasView {
        BoardCanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    /// The paper rule layer is what `updateBackground` touches, so scribbling on
    /// it and re-setting the same value shows whether the work re-ran.
    private func paperLayer(in view: BoardCanvasView) throws -> CALayer {
        let content = try XCTUnwrap(view.layer?.sublayers?.first { layer in
            layer.sublayers?.contains { $0.zPosition == -1_000_000 } == true
        })
        return try XCTUnwrap(content.sublayers?.first { $0.zPosition == -1_000_000 })
    }

    func testRepeatedSetPaperIsANoOp() throws {
        let view = makeView()
        view.setPaper(true)
        let paper = try paperLayer(in: view)
        XCTAssertFalse(paper.isHidden)

        paper.isHidden = true
        view.setPaper(true)
        XCTAssertTrue(paper.isHidden, "setting the same paper value re-ran the background work")

        view.setPaper(false)
        view.setPaper(true)
        XCTAssertFalse(paper.isHidden, "a real change stopped applying")
    }

    func testRepeatedSetTransparentIsANoOp() throws {
        let view = makeView()
        view.setPaper(true)
        view.setTransparent(true)
        let paper = try paperLayer(in: view)
        XCTAssertTrue(paper.isHidden)

        paper.isHidden = false
        view.setTransparent(true)
        XCTAssertFalse(paper.isHidden, "setting the same transparency re-ran the background work")

        view.setTransparent(false)
        XCTAssertFalse(paper.isHidden)
        view.setTransparent(true)
        XCTAssertTrue(paper.isHidden, "a real change stopped applying")
    }

    func testRepeatedSetXPBackgroundIsANoOp() throws {
        let view = makeView()
        view.setXPBackground(true)
        let paper = try paperLayer(in: view)

        paper.isHidden = false
        view.setXPBackground(true)
        XCTAssertFalse(paper.isHidden, "setting the same XP value re-ran the background work")

        view.setPaper(true)
        view.setXPBackground(false)
        XCTAssertFalse(paper.isHidden, "a real change stopped applying")
    }

    /// The pan toggle grabs first responder. Called on every render, it stole
    /// focus back from whatever the user had just clicked into.
    func testRepeatedSetGlobalPanEnabledDoesNotStealFirstResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        let view = makeView()
        window.contentView?.addSubview(view)

        view.setGlobalPanEnabled(true)
        XCTAssertTrue(window.firstResponder === view)

        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        window.contentView?.addSubview(other)
        window.makeFirstResponder(other)
        XCTAssertFalse(window.firstResponder === view)

        view.setGlobalPanEnabled(true)
        XCTAssertFalse(window.firstResponder === view, "an unchanged value grabbed first responder again")

        view.setGlobalPanEnabled(false)
        view.setGlobalPanEnabled(true)
        XCTAssertTrue(window.firstResponder === view, "a real change stopped applying")
    }
}
