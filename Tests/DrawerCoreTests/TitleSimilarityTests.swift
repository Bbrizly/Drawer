import XCTest
@testable import DrawerCore

final class TitleSimilarityTests: XCTestCase {
    // MARK: normalize

    func testNormalizeLowercasesAndCollapsesWhitespace() {
        XCTAssertEqual(TitleSimilarity.normalize("  Fix   Parser\t"), "fix parser")
    }

    func testNormalizeStripsEditedMarker() {
        XCTAssertEqual(
            TitleSimilarity.normalize("Notes.md - Edited"),
            TitleSimilarity.normalize("Notes.md")
        )
    }

    func testNormalizeStripsModifiedDotAndAsterisk() {
        let base = TitleSimilarity.normalize("Draft")
        XCTAssertEqual(TitleSimilarity.normalize("Draft •"), base)
        XCTAssertEqual(TitleSimilarity.normalize("Draft *"), base)
        XCTAssertEqual(TitleSimilarity.normalize("• Draft"), base)
    }

    // MARK: score

    func testScoreIdenticalIsOne() {
        XCTAssertEqual(TitleSimilarity.score("Fix parser", "fix   parser"), 1.0, accuracy: 0.0001)
    }

    func testScoreDisjointIsZero() {
        XCTAssertEqual(TitleSimilarity.score("apples oranges", "trucks planes"), 0.0)
    }

    func testScoreEmptyIsZero() {
        XCTAssertEqual(TitleSimilarity.score("", "anything"), 0.0)
        XCTAssertEqual(TitleSimilarity.score("x", ""), 0.0)
    }

    /// The canonical case from spec 02: an editor showing TodoParser.swift while
    /// "Fix parser" is an open task must score high enough to suggest, with no
    /// model. Needs camelCase + punctuation splitting so "parser" surfaces.
    func testScoreCanonicalCamelCaseFilename() {
        XCTAssertGreaterThanOrEqual(
            TitleSimilarity.score("TodoParser.swift — Drawer", "Fix parser"),
            0.5
        )
    }

    /// Short task title fully contained in a longer window title scores 1.0
    /// (overlap relative to the smaller set), so the shorter side drives it.
    func testScoreSubsetIsOne() {
        XCTAssertEqual(TitleSimilarity.score("Weekly budget review — Numbers", "budget review"), 1.0)
    }
}
