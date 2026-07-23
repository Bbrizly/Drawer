import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Drawer

/// The rule behind "your shortcut can be just ⌥": one modifier down, the same
/// one up, nothing else touched in between.
final class LoneModifierTrackerTests: XCTestCase {
    private let option = UInt16(kVK_Option)
    private let control = UInt16(kVK_Control)

    func testOneModifierDownAndUpIsATap() {
        var tracker = LoneModifierTracker()
        XCTAssertNil(tracker.changed(flags: [.option], keyCode: option))
        XCTAssertEqual(tracker.changed(flags: [], keyCode: option), option)
    }

    func testSecondModifierMakesItACombination() {
        var tracker = LoneModifierTracker()
        _ = tracker.changed(flags: [.control], keyCode: control)
        _ = tracker.changed(flags: [.control, .option], keyCode: option)
        _ = tracker.changed(flags: [.control], keyCode: option)
        XCTAssertNil(tracker.changed(flags: [], keyCode: control))
    }

    func testAKeyPressCancelsTheTap() {
        var tracker = LoneModifierTracker()
        _ = tracker.changed(flags: [.option], keyCode: option)
        tracker.keyPressed()
        XCTAssertNil(tracker.changed(flags: [], keyCode: option))
    }

    func testItStartsOverAfterEachRelease() {
        var tracker = LoneModifierTracker()
        _ = tracker.changed(flags: [.option], keyCode: option)
        tracker.keyPressed()
        _ = tracker.changed(flags: [], keyCode: option)

        _ = tracker.changed(flags: [.option], keyCode: option)
        XCTAssertEqual(tracker.changed(flags: [], keyCode: option), option)
    }
}
