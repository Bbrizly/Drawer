import Foundation

/// Shared title normalization and token-overlap scoring. One implementation so
/// the attribution sessionizer (clusters window titles), the attribution
/// classifier (matches titles to tasks), and the planner calibration (finds
/// similar past tasks) all agree on what "the same title" and "how similar"
/// mean. Written once, tested once.
public enum TitleSimilarity {
    /// Lowercased, document-modified markers stripped, whitespace collapsed.
    /// Two titlebars that differ only by a "— Edited" suffix or a modified
    /// dot normalize equal, so a flapping titlebar reads as one title.
    public static func normalize(_ title: String) -> String {
        var s = title.lowercased()
        // macOS / Obsidian append these to signal unsaved changes.
        for marker in [" — edited", " - edited"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        // Modified-dot and asterisk markers, wherever they sit.
        s = s.replacingOccurrences(of: "•", with: " ")
        s = s.replacingOccurrences(of: "*", with: " ")
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Token-overlap score in 0...1: how many of the shorter title's words the
    /// longer one contains (overlap coefficient). camelCase and punctuation
    /// split into tokens, so "TodoParser.swift" yields "parser" and matches a
    /// "Fix parser" task without a model. 0 when either side has no tokens.
    public static func score(_ a: String, _ b: String) -> Double {
        let ta = tokens(a)
        let tb = tokens(b)
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let overlap = ta.intersection(tb).count
        return Double(overlap) / Double(min(ta.count, tb.count))
    }

    /// Words in a title: camelCase humps split, punctuation split, lowercased,
    /// single characters dropped as noise.
    static func tokens(_ title: String) -> Set<String> {
        Set(
            splitCamelCase(title)
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 2 }
        )
    }

    /// Inserts a space at each lowercase→uppercase boundary so "TodoParser"
    /// becomes "Todo Parser". Everything else is left for the punctuation split.
    private static func splitCamelCase(_ s: String) -> String {
        var out = ""
        var prev: Character?
        for c in s {
            if let p = prev, p.isLowercase, c.isUppercase { out.append(" ") }
            out.append(c)
            prev = c
        }
        return out
    }
}
