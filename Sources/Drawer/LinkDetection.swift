import Foundation

/// Turns a plain string into an AttributedString with any URLs marked as
/// tappable links. SwiftUI's Text renders these as real links that open in the
/// browser, so a note like "see https://example.com" becomes clickable.
func linkified(_ string: String) -> AttributedString {
    var attributed = AttributedString(string)
    guard let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    ) else {
        return attributed
    }
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    for match in detector.matches(in: string, options: [], range: range) {
        guard let url = match.url,
              let stringRange = Range(match.range, in: string),
              let low = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let high = AttributedString.Index(stringRange.upperBound, within: attributed)
        else { continue }
        attributed[low..<high].link = url
        attributed[low..<high].underlineStyle = .single
    }
    return attributed
}
