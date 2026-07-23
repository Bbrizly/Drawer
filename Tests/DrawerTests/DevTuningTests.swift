import XCTest
@testable import Drawer

@MainActor
final class DevTuningTests: XCTestCase {
    /// The copy button is only useful if what lands on the clipboard is Swift
    /// that can be pasted straight over the defaults.
    func testSwiftSourceReadsLikeTheCode() {
        let swift = DevTuning.standard.swiftSource
        XCTAssertTrue(swift.contains("var size: CGFloat = 144"), swift)
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

    /// A number saved on a dev machine must not reach anyone else, so with the
    /// switch off the store hands back exactly what the code says.
    func testShippedBuildIgnoresSavedTuning() {
        guard !DevTools.enabled else { return }
        XCTAssertEqual(DevTuningStore.shared.tuning, .standard)
    }
}
