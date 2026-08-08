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
    /// Set from a lone colour token in the heading paren: `## Apps (blue)`.
    /// Every card in the bay wears it unless the card names its own.
    public var color: String?
    public var ideas: [ParkedIdea]

    public init(name: String, color: String? = nil, ideas: [ParkedIdea]) {
        self.name = name
        self.color = color
        self.ideas = ideas
    }
}

public struct ParkingLotDocument: Equatable {
    public var bays: [ParkingBay]
    public init(bays: [ParkingBay] = []) { self.bays = bays }
}

/// Reads Parking lot.md. `##` is a bay, `- ` is an idea, indented lines under
/// an idea are its details until the next blank line, the same rule the task
/// file uses. The trailing paren holds an optional date and colour in either
/// order; anything else in it is just title text and comes back untouched.
///
/// No regex anywhere. `Regex.firstMatch` per line showed up as the whole of a
/// main-thread hang once already in this app, and every rule here is a prefix
/// or a suffix test that plain string work does for a fraction of the cost.
public enum ParkingLotParser {
    /// The exact keys BoardItem.color uses. No second colour vocabulary.
    public static let colors: Set<String> = ["yellow", "pink", "blue", "green", "purple", "gray"]

    public static func parse(_ text: String) -> ParkingLotDocument {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        var bays: [ParkingBay] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let (name, color) = bayHeading(heading)
                bays.append(ParkingBay(name: name, color: color, ideas: []))
                i += 1
                continue
            }
            guard !bays.isEmpty, line.hasPrefix("- "), line.count > 2 else {
                i += 1
                continue
            }
            let meta = ideaMeta(String(line.dropFirst(2)))
            var detailLines: [String] = []
            var j = i + 1
            while j < lines.count, isDetailLine(lines[j]) {
                detailLines.append(lines[j].trimmingCharacters(in: .whitespaces))
                j += 1
            }
            bays[bays.count - 1].ideas.append(ParkedIdea(
                title: meta.title,
                details: detailLines.joined(separator: "\n"),
                parked: meta.parked,
                color: meta.color,
                lineRange: i..<j
            ))
            i = j
        }
        return ParkingLotDocument(bays: bays)
    }

    /// Splits `Apps (blue)` into a name and a bay colour. Only a lone colour
    /// token counts; `Apps (later)` keeps its paren as part of the name.
    public static func bayHeading(_ heading: String) -> (name: String, color: String?) {
        guard let paren = trailingParen(heading), colors.contains(paren.body) else {
            return (heading, nil)
        }
        let name = paren.head.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (heading, nil) : (name, paren.body)
    }

    /// Splits an idea's text into title, parked date, and colour. The paren has
    /// to hold nothing but recognised tokens, or it is title text.
    static func ideaMeta(_ text: String) -> (title: String, parked: String?, color: String?) {
        guard let paren = trailingParen(text) else { return (text, nil, nil) }
        var date: String?
        var color: String?
        let tokens = paren.body.split(separator: " ")
        guard !tokens.isEmpty else { return (text, nil, nil) }
        for token in tokens {
            let token = String(token)
            if date == nil, TodoParser.isValidDate(token) {
                date = token
            } else if color == nil, colors.contains(token) {
                color = token
            } else {
                return (text, nil, nil)
            }
        }
        return (paren.head.trimmingCharacters(in: .whitespaces), date, color)
    }

    /// The `(...)` at the very end of a line, and what comes before it. Nil
    /// when there is no trailing paren or when it nests another one.
    private static func trailingParen(_ text: String) -> (head: String, body: String)? {
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return nil }
        let body = text[text.index(after: open)..<text.index(before: text.endIndex)]
        guard !body.contains(")") else { return nil }
        return (String(text[..<open]), String(body))
    }

    /// Indented and not blank, same shape as TodoParser.isDescriptionLine.
    static func isDetailLine(_ text: String) -> Bool {
        guard let first = text.first, first == " " || first == "\t" else { return false }
        return !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Pure layout math for the lot view: a bay's ideas laid out left to right,
/// wrapping at the window edge, file order preserved.
public enum ParkingLotLayout {
    /// Rows a bay occupies. Only what its cars need, never a reserved empty
    /// row: with a lot of bays those spare rows added up to a third of the
    /// lot's height. Parking into a full bay goes through the sign's + button.
    public static func rows(ideas: Int, perRow: Int) -> Int {
        guard perRow > 0 else { return 1 }
        return max(1, (max(0, ideas) + perRow - 1) / perRow)
    }
}
