import AppKit
import XCTest
@testable import DrawerBureau

/// R5 aging: paper that sat in the drawer yellows; the age is derived from
/// when the slip printed, and an aged render actually differs from a fresh one.
@MainActor
final class BureauAgingTests: XCTestCase {
    private let slip = CGSize(width: 150, height: 84)

    func testAgeFactorGrowsFromPrintDateAndCapsAtTwoWeeks() {
        let now = Date()
        var link = ReceiptLink(textSnapshot: "x", sectionDate: "2026-07-13")
        link.printedAt = now
        XCTAssertEqual(link.ageFactor(now: now), 0, accuracy: 0.01)
        link.printedAt = now.addingTimeInterval(-7 * 86_400)
        XCTAssertEqual(link.ageFactor(now: now), 0.5, accuracy: 0.01)
        link.printedAt = now.addingTimeInterval(-40 * 86_400)
        XCTAssertEqual(link.ageFactor(now: now), 1)
    }

    func testAgeFactorFallsBackToCreatedAt() {
        let now = Date()
        let link = ReceiptLink(
            textSnapshot: "x", sectionDate: "2026-07-13",
            createdAt: now.addingTimeInterval(-14 * 86_400)
        )
        XCTAssertEqual(link.ageFactor(now: now), 1)
    }

    /// An aged slip is a different (cached) render from a fresh one, and small
    /// age changes inside a bucket do not thrash the cache.
    func testAgedRenderDiffersAndBucketsCache() {
        let renderer = TextureRenderer()
        let fresh = renderer.image(title: "same", size: slip, scale: 2)
        let aged = renderer.image(title: "same", size: slip, scale: 2, age: 1)
        XCTAssertFalse(fresh === aged)
        // Within one bucket (quarters), the cache hit holds.
        let a = renderer.image(title: "same", size: slip, scale: 2, age: 0.95)
        XCTAssertTrue(aged === a)
    }

    /// The tuning panel's write path publishes and persists in one step.
    func testTuningUpdateWritesTheJson() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let tuning = BureauTuning(directory: dir)
        var doc = tuning.document
        doc.transition.pushMs = 512
        tuning.update(doc)
        XCTAssertEqual(tuning.document.transition.pushMs, 512)

        let reloaded = BureauTuning(directory: dir)
        XCTAssertEqual(reloaded.document.transition.pushMs, 512)
    }
}
