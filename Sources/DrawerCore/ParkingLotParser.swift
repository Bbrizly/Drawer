import Foundation

/// One idea in the lot. `lineRange` covers the bullet line plus its indented
/// detail lines, for surgical writeback.
public struct ParkedIdea: Equatable {
    public var title: String
    public var details: String
    /// YYYY-MM-DD, matching the codebase's string day keys.
    public var parked: String?
    public var color: String?
    public var lineRange: Range<Int>
}

public struct ParkingBay: Equatable {
    public var name: String
    public var ideas: [ParkedIdea]
}

public struct ParkingLotDocument: Equatable {
    public var bays: [ParkingBay]
    public init(bays: [ParkingBay] = []) { self.bays = bays }
}

/// Reads Parking lot.md. `##` is a bay, `- ` is an idea, indented lines under
/// an idea are its details until the next blank line, the same rule the task
/// file uses. The trailing paren holds an optional date and colour in either
/// order; anything else in it is just title text and comes back untouched.
public enum ParkingLotParser {
    /// The exact keys BoardItem.color uses. No second colour vocabulary.
    public static let colors: Set<String> = ["yellow", "pink", "blue", "green", "purple", "gray"]

    private static let ideaRegex = #/^- (.+)$/#
    private static let metaRegex = #/\s*\(([^()]*)\)$/#

    public static func parse(_ text: String) -> ParkingLotDocument {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var bays: [ParkingBay] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("## ") {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                bays.append(ParkingBay(name: name, ideas: []))
                i += 1
                continue
            }
            guard !bays.isEmpty, let m = line.wholeMatch(of: ideaRegex) else {
                i += 1
                continue
            }
            var title = String(m.1)
            var parked: String?
            var color: String?
            if let meta = title.firstMatch(of: metaRegex) {
                let tokens = meta.1.split(separator: " ").map(String.init)
                var date: String?
                var col: String?
                var recognised = !tokens.isEmpty
                for token in tokens {
                    if date == nil, TodoParser.isValidDate(token) {
                        date = token
                    } else if col == nil, colors.contains(token) {
                        col = token
                    } else {
                        recognised = false
                        break
                    }
                }
                if recognised {
                    parked = date
                    color = col
                    title = String(title[..<meta.range.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            var detailLines: [String] = []
            var j = i + 1
            while j < lines.count, isDetailLine(lines[j]) {
                detailLines.append(lines[j].trimmingCharacters(in: .whitespaces))
                j += 1
            }
            bays[bays.count - 1].ideas.append(ParkedIdea(
                title: title,
                details: detailLines.joined(separator: "\n"),
                parked: parked,
                color: color,
                lineRange: i..<j
            ))
            i = j
        }
        return ParkingLotDocument(bays: bays)
    }

    /// Indented and not blank, same shape as TodoParser.isDescriptionLine.
    static func isDetailLine(_ text: String) -> Bool {
        guard let first = text.first, first == " " || first == "\t" else { return false }
        return !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Pure layout math for the lot view: a bay's ideas chunked into columns of
/// stalls, file order preserved, top to bottom then the next block right.
public enum ParkingLotLayout {
    public static func columns(_ count: Int, stallsPerColumn: Int) -> [Range<Int>] {
        guard count > 0, stallsPerColumn > 0 else { return [] }
        return stride(from: 0, to: count, by: stallsPerColumn)
            .map { $0..<min($0 + stallsPerColumn, count) }
    }
}
