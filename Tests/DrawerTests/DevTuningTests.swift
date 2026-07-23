import XCTest
@testable import Drawer

@MainActor
final class DevTuningTests: XCTestCase {
    /// The copy button is only useful if what lands on the clipboard is Swift
    /// that can be pasted straight over the defaults.
    func testSwiftSourceReadsLikeTheCode() {
        let swift = DevTuning.standard.swiftSource
        XCTAssertTrue(swift.contains("var size: CGFloat = 144"), swift)
        XCTAssertTrue(swift.contains("var openSize: CGFloat = 168"), swift)
        XCTAssertTrue(swift.contains("var punch: CGFloat = 0.93"), swift)
        XCTAssertTrue(
            swift.contains("withAnimation(.easeInOut(duration: 0.22)) { step = next }"), swift)
        XCTAssertTrue(swift.contains("controlPoints: 0.16, 1, 0.3, 1)"), swift)
        XCTAssertTrue(swift.contains("controlPoints: 0.4, 0, 1, 1)"), swift)
    }

    func testTunedNumbersSurviveAnEncodeAndDecode() throws {
        var tuning = DevTuning.standard
        tuning.mark.size = 180
        tuning.slideOut.x1 = 0.7
        let back = try JSONDecoder().decode(
            DevTuning.self, from: JSONEncoder().encode(tuning))
        XCTAssertEqual(back, tuning)
    }

    /// One drag changes the tuning many times a second. Writing each step to
    /// UserDefaults woke the whole app per frame, which froze it mid drag and
    /// ate the shortcut while it was frozen. The sliders move now, the saving
    /// waits for the hand to stop.
    func testDraggingASliderDoesNotSavePerStep() async {
        guard DevTools.enabled else { return }
        let store = DevTuningStore.shared
        store.reset()
        for size in stride(from: CGFloat(100), through: 160, by: 2) {
            store.tuning.mark.size = size
        }
        XCTAssertNil(
            UserDefaults.standard.data(forKey: "devTuning"), "saved while the hand was moving")
        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertNotNil(
            UserDefaults.standard.data(forKey: "devTuning"), "never saved once it settled")
        store.reset()
    }

    /// A number saved on a dev machine must not reach anyone else, so with the
    /// switch off the store hands back exactly what the code says.
    func testShippedBuildIgnoresSavedTuning() {
        guard !DevTools.enabled else { return }
        XCTAssertEqual(DevTuningStore.shared.tuning, .standard)
    }
}
