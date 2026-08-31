import Foundation

public extension TodoWriteback {
    /// Moves one exact checkbox task (including its indented note block) to a
    /// different Drawer section in a single pure transform. Keeping delete and
    /// insert inside one transform matters for iCloud/Obsidian callers: a CAS
    /// retry can replay the whole logical move against fresh bytes without ever
    /// exposing an intermediate state where the task has vanished.
    static func move(
        line rawLine: String,
        sectionDate: String,
        occurrence: Int = 0,
        toSectionKey destinationKey: String,
        displayHeading: String,
        in data: Data
    ) throws -> Data {
        guard !rawLine.isEmpty else { throw WritebackError.lineNotFound }
        if sectionDate == destinationKey { return data }

        let sourceLines = try moveMarkdownLines(in: data)
        let sourceRoles = TodoParser.lineRoles(sourceLines.map(\.text))
        var currentKey: String?
        var seen = 0
        var sourceRange: Range<Data.Index>?

        for index in sourceLines.indices {
            let line = sourceLines[index]
            switch sourceRoles[index] {
            case .fence, .fenced:
                continue
            case .heading:
                currentKey = TodoParser.sectionKey(fromHeading: line.text)
                continue
            default:
                break
            }

            guard sourceRoles[index] == .task,
                  currentKey == sectionDate,
                  line.text == rawLine
            else { continue }
            if seen < occurrence {
                seen += 1
                continue
            }

            var upper = line.fullRange.upperBound
            var next = index + 1
            while next < sourceLines.endIndex, sourceRoles[next] == .note {
                upper = sourceLines[next].fullRange.upperBound
                next += 1
            }
            sourceRange = line.fullRange.lowerBound..<upper
            break
        }

        guard let sourceRange else { throw WritebackError.lineNotFound }

        let newline = movePreferredNewline(in: sourceLines, data: data)
        var block = Data(data[sourceRange])
        if block.isEmpty || !moveIsLineEnding(block[block.index(before: block.endIndex)]) {
            block.append(newline)
        }

        var out = data
        out.removeSubrange(sourceRange)

        let destinationLines = try moveMarkdownLines(in: out)
        let destinationRoles = TodoParser.lineRoles(destinationLines.map(\.text))
        var headingIndex: Int?
        var nextHeadingIndex: Int?

        for index in destinationLines.indices where destinationRoles[index] == .heading {
            if headingIndex != nil {
                nextHeadingIndex = index
                break
            }
            if TodoParser.sectionKey(fromHeading: destinationLines[index].text) == destinationKey {
                headingIndex = index
            }
        }

        guard let headingIndex else {
            if moveHasContentBeyondBOM(out) {
                let trailing = moveTrailingNewlineCount(in: out)
                if trailing == 0 { out.append(newline) }
                if trailing < 2 { out.append(newline) }
            }
            out.append(Data(("## " + displayHeading).utf8))
            out.append(newline)
            out.append(block)
            return out
        }

        var insertIndex = nextHeadingIndex ?? destinationLines.endIndex
        while insertIndex > headingIndex + 1 && destinationLines[insertIndex - 1].text.isEmpty {
            insertIndex -= 1
        }
        let offset = insertIndex < destinationLines.endIndex
            ? destinationLines[insertIndex].contentRange.lowerBound
            : out.endIndex

        var insertion = Data()
        if offset > out.startIndex && !moveIsLineEnding(out[out.index(before: offset)]) {
            insertion.append(newline)
        }
        insertion.append(block)
        out.insert(contentsOf: insertion, at: offset)
        return out
    }
}

private struct MoveMarkdownLine {
    let contentRange: Range<Data.Index>
    let fullRange: Range<Data.Index>
    let text: String
}

private func moveMarkdownLines(in data: Data) throws -> [MoveMarkdownLine] {
    guard String(data: data, encoding: .utf8) != nil else {
        throw WritebackError.badEncoding
    }

    var lines: [MoveMarkdownLine] = []
    var lineStart = data.startIndex
    var index = lineStart

    while index < data.endIndex {
        guard moveIsLineEnding(data[index]) else {
            index = data.index(after: index)
            continue
        }

        let contentEnd = index
        var lineEnd = data.index(after: index)
        if data[index] == UInt8(ascii: "\r"),
           lineEnd < data.endIndex,
           data[lineEnd] == UInt8(ascii: "\n") {
            lineEnd = data.index(after: lineEnd)
        }
        lines.append(MoveMarkdownLine(
            contentRange: lineStart..<contentEnd,
            fullRange: lineStart..<lineEnd,
            text: String(data: data[lineStart..<contentEnd], encoding: .utf8) ?? ""
        ))
        lineStart = lineEnd
        index = lineEnd
    }

    if lineStart < data.endIndex {
        lines.append(MoveMarkdownLine(
            contentRange: lineStart..<data.endIndex,
            fullRange: lineStart..<data.endIndex,
            text: String(data: data[lineStart..<data.endIndex], encoding: .utf8) ?? ""
        ))
    }
    return lines
}

private func movePreferredNewline(in lines: [MoveMarkdownLine], data: Data) -> Data {
    for line in lines where line.fullRange.upperBound > line.contentRange.upperBound {
        return Data(data[line.contentRange.upperBound..<line.fullRange.upperBound])
    }
    return Data([UInt8(ascii: "\n")])
}

private func moveHasContentBeyondBOM(_ data: Data) -> Bool {
    let bom = Data([0xEF, 0xBB, 0xBF])
    return !data.isEmpty && data != bom
}

private func moveTrailingNewlineCount(in data: Data) -> Int {
    var count = 0
    var index = data.endIndex
    while index > data.startIndex {
        let previous = data.index(before: index)
        if data[previous] == UInt8(ascii: "\n") {
            index = previous
            if index > data.startIndex {
                let possibleCR = data.index(before: index)
                if data[possibleCR] == UInt8(ascii: "\r") { index = possibleCR }
            }
            count += 1
        } else if data[previous] == UInt8(ascii: "\r") {
            index = previous
            count += 1
        } else {
            break
        }
    }
    return count
}

private func moveIsLineEnding(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
}
