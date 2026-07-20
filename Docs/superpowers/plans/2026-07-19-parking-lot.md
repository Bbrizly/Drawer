# Parking Lot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pinned "Parking lot" board that renders the ideas in a hand-writable `Parking lot.md` as top-down GTA-style cars in painted stalls, with press-to-pull-out editing and markdown writeback.

**Architecture:** DrawerCore gains a parser, a writeback splicer, and a store that mirror `TodoParser`, `TodoWriteback`, and `NotesStore`. The UI is a plain `ScrollView` with a magnification gesture (no `BoardCanvas`), mounted inside `IdeaBoardPage` when the pinned selector row is chosen. Capture retargets `Park ◂` from `board.json` to the lot file.

**Tech Stack:** Swift, SwiftUI, SPM. Tests in `Tests/DrawerCoreTests` with XCTest.

**Spec:** `Docs/superpowers/specs/2026-07-19-parking-lot-design.md`

**One deviation from the spec, on purpose:** `ParkedIdea.parked` is a `String?` holding `YYYY-MM-DD`, not a `Date?`. The whole codebase treats day keys as ISO strings (`TodoParser.sectionDate`, `TodoStore.localToday`) and writeback needs the exact original text back. A `Date` would only add a formatter round trip.

## Global Constraints

- Build and test: `swift build` then `swift test`. Release: `make app`, `make install`, then quit and reopen the app.
- Commits: plain present-tense sentences, very simple English, no em dashes, no emoji, no `feat:`/`fix:` prefixes, no co-author, no tool credit.
- Colour vocabulary is exactly `yellow pink blue green purple gray`, the keys `BoardItem.color` uses. Render via `Palette.card(key).color` (nil = yellow).
- The lot file is `Parking lot.md` in the same directory as the resolved drawer file (`AppPaths.drawerFile`).
- Everything is behind `FeatureFlag.parkingLot` (`feature.parkingLot`), default off.
- Unrecognised lines in the lot file are never rewritten. Writeback splices line ranges, never re-serialises the document.
- Do not touch `BoardCanvas`, `BoardStore`, or `board.json` formats. The lot is a separate system.
- The working tree currently has unrelated dirty files (`DrawerIconButton.swift`, `DrawerView.swift`, `PomodoroHeaderView.swift`, `SettingsView.swift`, `TimerHeaderView.swift`). Do not commit them as part of any task below; stage only the files each task names.

---

### Task 1: ParkingLotParser

**Files:**
- Create: `Sources/DrawerCore/ParkingLotParser.swift`
- Test: `Tests/DrawerCoreTests/ParkingLotParserTests.swift`

**Interfaces:**
- Consumes: `TodoParser.isValidDate(_:)` (internal to DrawerCore, already exists).
- Produces: `ParkedIdea` (`title: String`, `details: String`, `parked: String?`, `color: String?`, `lineRange: Range<Int>`), `ParkingBay` (`name: String`, `ideas: [ParkedIdea]`), `ParkingLotDocument` (`bays: [ParkingBay]`), `ParkingLotParser.parse(_ text: String) -> ParkingLotDocument`, `ParkingLotParser.colors: Set<String>`, `ParkingLotLayout.columns(_ count: Int, stallsPerColumn: Int) -> [Range<Int>]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DrawerCoreTests/ParkingLotParserTests.swift`:

```swift
import XCTest

@testable import DrawerCore

final class ParkingLotParserTests: XCTestCase {
    func testParsesBaysIdeasAndDetails() {
        let text = """
        ## Apps
        - Lock screen widget (2026-07-19 yellow)
            A tiny glanceable version.
            Just the next task.
        - Pluck for Instagram (2026-03-02 pink)

        ## Hardware
        - Build a macropad (2026-05-11 blue)
        """
        let doc = ParkingLotParser.parse(text)
        XCTAssertEqual(doc.bays.map(\.name), ["Apps", "Hardware"])
        XCTAssertEqual(doc.bays[0].ideas.count, 2)
        let first = doc.bays[0].ideas[0]
        XCTAssertEqual(first.title, "Lock screen widget")
        XCTAssertEqual(first.parked, "2026-07-19")
        XCTAssertEqual(first.color, "yellow")
        XCTAssertEqual(first.details, "A tiny glanceable version.\nJust the next task.")
        XCTAssertEqual(first.lineRange, 1..<4)
        XCTAssertEqual(doc.bays[1].ideas[0].title, "Build a macropad")
    }

    func testMetadataVariants() {
        let doc = ParkingLotParser.parse("""
        ## Bay
        - Date only (2026-01-02)
        - Color only (pink)
        - Reversed (pink 2026-01-02)
        - Neither
        - Junk (soon)
        - Bad date (2026-13-99)
        """)
        let i = doc.bays[0].ideas
        XCTAssertEqual(i[0].parked, "2026-01-02")
        XCTAssertNil(i[0].color)
        XCTAssertEqual(i[1].color, "pink")
        XCTAssertNil(i[1].parked)
        XCTAssertEqual(i[2].color, "pink")
        XCTAssertEqual(i[2].parked, "2026-01-02")
        XCTAssertNil(i[3].parked)
        XCTAssertNil(i[3].color)
        XCTAssertEqual(i[3].title, "Neither")
        XCTAssertEqual(i[4].title, "Junk (soon)")
        XCTAssertEqual(i[5].title, "Bad date (2026-13-99)")
    }

    func testDetailsStopAtBlankLine() {
        let doc = ParkingLotParser.parse("""
        ## Bay
        - Idea
            first
            second

            stray indented prose
        - Next
        """)
        XCTAssertEqual(doc.bays[0].ideas[0].details, "first\nsecond")
        XCTAssertEqual(doc.bays[0].ideas.count, 2)
    }

    func testIgnoresLinesOutsideBays() {
        let doc = ParkingLotParser.parse("- Orphan idea\nprose\n## Bay\n- Real")
        XCTAssertEqual(doc.bays.count, 1)
        XCTAssertEqual(doc.bays[0].ideas.map(\.title), ["Real"])
    }

    func testColumnsChunking() {
        XCTAssertEqual(ParkingLotLayout.columns(7, stallsPerColumn: 3), [0..<3, 3..<6, 6..<7])
        XCTAssertEqual(ParkingLotLayout.columns(3, stallsPerColumn: 3), [0..<3])
        XCTAssertEqual(ParkingLotLayout.columns(0, stallsPerColumn: 3), [])
        XCTAssertEqual(ParkingLotLayout.columns(2, stallsPerColumn: 0), [])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ParkingLotParserTests`
Expected: compile error, `ParkingLotParser` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/DrawerCore/ParkingLotParser.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ParkingLotParserTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DrawerCore/ParkingLotParser.swift Tests/DrawerCoreTests/ParkingLotParserTests.swift
git commit -m "Parse the parking lot file"
```

---

### Task 2: ParkingLotWriteback

**Files:**
- Create: `Sources/DrawerCore/ParkingLotWriteback.swift`
- Test: `Tests/DrawerCoreTests/ParkingLotWritebackTests.swift`

**Interfaces:**
- Consumes: `ParkedIdea` from Task 1.
- Produces: `ParkingLotWriteback.serialize(title:details:parked:color:) -> [String]`, `.replace(_ idea:in:title:details:color:) -> String`, `.delete(_ idea:in:) -> String`, `.append(title:details:parked:color:toBay:in:) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DrawerCoreTests/ParkingLotWritebackTests.swift`:

```swift
import XCTest

@testable import DrawerCore

final class ParkingLotWritebackTests: XCTestCase {
    let canonical = """
    Intro prose the parser ignores.

    ## Apps
    - Lock screen widget (2026-07-19 yellow)
        A tiny glanceable version.
    - Pluck for Instagram (2026-03-02 pink)

    ## Hardware
    - Build a macropad (2026-05-11 blue)
    """

    func testRoundTripIsByteIdentical() {
        var text = canonical
        // Re-serialise every idea in place with unchanged content. Reversed so
        // earlier line ranges stay valid while later ones are spliced.
        for bay in ParkingLotParser.parse(text).bays.reversed() {
            for idea in bay.ideas.reversed() {
                text = ParkingLotWriteback.replace(
                    idea, in: text,
                    title: idea.title, details: idea.details, color: idea.color)
            }
        }
        XCTAssertEqual(text, canonical)
    }

    func testEditSplicesOnlyThatIdea() {
        let doc = ParkingLotParser.parse(canonical)
        let out = ParkingLotWriteback.replace(
            doc.bays[0].ideas[1], in: canonical,
            title: "Pluck for IG", details: "Check the API first.", color: "blue")
        XCTAssertTrue(out.contains("Intro prose the parser ignores."))
        XCTAssertTrue(out.contains("- Pluck for IG (2026-03-02 blue)\n    Check the API first."))
        XCTAssertTrue(out.contains("- Lock screen widget (2026-07-19 yellow)"))
        XCTAssertTrue(out.contains("## Hardware"))
    }

    func testDeleteRemovesIdeaAndDetails() {
        let doc = ParkingLotParser.parse(canonical)
        let out = ParkingLotWriteback.delete(doc.bays[0].ideas[0], in: canonical)
        XCTAssertFalse(out.contains("Lock screen widget"))
        XCTAssertFalse(out.contains("glanceable"))
        XCTAssertTrue(out.contains("- Pluck for Instagram (2026-03-02 pink)"))
    }

    func testAppendToExistingBay() {
        let out = ParkingLotWriteback.append(
            title: "New idea", details: "", parked: "2026-07-19", color: nil,
            toBay: "Apps", in: canonical)
        let doc = ParkingLotParser.parse(out)
        XCTAssertEqual(doc.bays[0].ideas.last?.title, "New idea")
        XCTAssertEqual(doc.bays[1].ideas.count, 1)
    }

    func testAppendCreatesMissingBayAtTop() {
        let out = ParkingLotWriteback.append(
            title: "Loose", details: "", parked: "2026-07-19", color: nil,
            toBay: "Unsorted", in: canonical)
        XCTAssertTrue(out.hasPrefix("## Unsorted\n- Loose (2026-07-19)\n"))
        XCTAssertTrue(out.contains("Intro prose the parser ignores."))
    }

    func testSerializeWithoutMetadata() {
        XCTAssertEqual(
            ParkingLotWriteback.serialize(title: "Plain", details: "", parked: nil, color: nil),
            ["- Plain"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ParkingLotWritebackTests`
Expected: compile error, `ParkingLotWriteback` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/DrawerCore/ParkingLotWriteback.swift`:

```swift
import Foundation

/// Splices single-idea edits into the lot file, leaving every other line
/// byte-for-byte untouched. Same instinct as TodoWriteback: never
/// re-serialise the whole document, the file is the user's first.
public enum ParkingLotWriteback {
    /// Canonical lines for one idea: the bullet line, then detail lines
    /// indented four spaces. Blank detail lines are dropped because a blank
    /// line is what ends a note in this format.
    public static func serialize(
        title: String, details: String, parked: String?, color: String?
    ) -> [String] {
        let meta = [parked, color].compactMap { $0 }.joined(separator: " ")
        var lines = [meta.isEmpty ? "- \(title)" : "- \(title) (\(meta))"]
        for line in details.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("    " + line.trimmingCharacters(in: .whitespaces))
        }
        return lines
    }

    /// Replaces one idea's lines with fresh content. The parked date rides
    /// along unchanged; only the title, details, and colour are editable.
    public static func replace(
        _ idea: ParkedIdea, in text: String,
        title: String, details: String, color: String?
    ) -> String {
        splice(text, range: idea.lineRange,
               with: serialize(title: title, details: details, parked: idea.parked, color: color))
    }

    public static func delete(_ idea: ParkedIdea, in text: String) -> String {
        splice(text, range: idea.lineRange, with: [])
    }

    /// Appends an idea at the end of the named bay. A missing bay is created
    /// at the top of the file, which is where Unsorted lives.
    public static func append(
        title: String, details: String, parked: String?, color: String?,
        toBay bay: String, in text: String
    ) -> String {
        var lines = split(text)
        let ideaLines = serialize(title: title, details: details, parked: parked, color: color)
        if let h = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## \(bay)"
        }) {
            var end = h + 1
            while end < lines.count, !lines[end].hasPrefix("## ") { end += 1 }
            // Back over the blank lines that separate this bay from the next.
            var at = end
            while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                at -= 1
            }
            lines.insert(contentsOf: ideaLines, at: at)
        } else {
            lines.insert(contentsOf: ["## \(bay)"] + ideaLines + [""], at: 0)
        }
        return lines.joined(separator: "\n")
    }

    static func split(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    static func splice(_ text: String, range: Range<Int>, with newLines: [String]) -> String {
        var lines = split(text)
        guard range.lowerBound >= 0, range.upperBound <= lines.count else { return text }
        lines.replaceSubrange(range, with: newLines)
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ParkingLotWritebackTests`
Expected: 6 tests pass. Also run `swift test --filter ParkingLot` to keep Task 1 green.

- [ ] **Step 5: Commit**

```bash
git add Sources/DrawerCore/ParkingLotWriteback.swift Tests/DrawerCoreTests/ParkingLotWritebackTests.swift
git commit -m "Write parking lot edits back to the file"
```

---

### Task 3: ParkingLotStore

**Files:**
- Create: `Sources/DrawerCore/ParkingLotStore.swift`
- Test: `Tests/DrawerCoreTests/ParkingLotStoreTests.swift`

**Interfaces:**
- Consumes: `ParkingLotParser.parse`, `ParkingLotWriteback` (Tasks 1 and 2), `FileWatcher(directory:pollFile:)`, `TodoStore.localToday()`.
- Produces: `@MainActor ParkingLotStore: ObservableObject` with `document: ParkingLotDocument` (published, read-only), `ideaCount: Int`, `start()`, `load()`, `update(bayIndex:ideaIndex:title:details:color:)`, `delete(bayIndex:ideaIndex:)`, `move(bayIndex:ideaIndex:toBay:)`, `park(title:details:)`, `saveNow()`. Convenience init `ParkingLotStore(fileURL:debounce:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DrawerCoreTests/ParkingLotStoreTests.swift`:

```swift
import XCTest

@testable import DrawerCore

@MainActor
final class ParkingLotStoreTests: XCTestCase {
    private final class Disk {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private func makeStore(initial: String) -> (ParkingLotStore, Disk) {
        let disk = Disk(initial)
        let store = ParkingLotStore(
            fileURL: URL(fileURLWithPath: "/tmp/parking-lot-test.md"),
            debounce: 0,
            readString: { _ in disk.value },
            writeString: { value, _ in disk.value = value },
            todayProvider: { "2026-07-19" }
        )
        return (store, disk)
    }

    private let canonical = """
    ## Apps
    - Lock screen widget (2026-07-19 yellow)
        A tiny glanceable version.

    ## Hardware
    - Build a macropad (2026-05-11 blue)
    """

    func testLoadParsesFile() {
        let (store, _) = makeStore(initial: canonical)
        store.load()
        XCTAssertEqual(store.document.bays.map(\.name), ["Apps", "Hardware"])
        XCTAssertEqual(store.ideaCount, 2)
    }

    func testUpdateReparsesAndWrites() {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.update(bayIndex: 0, ideaIndex: 0,
                     title: "Lock widget", details: "Smaller scope.", color: "pink")
        XCTAssertEqual(store.document.bays[0].ideas[0].title, "Lock widget")
        store.saveNow()
        XCTAssertTrue(disk.value.contains("- Lock widget (2026-07-19 pink)\n    Smaller scope."))
        XCTAssertTrue(disk.value.contains("- Build a macropad (2026-05-11 blue)"))
    }

    func testParkCreatesUnsortedWithToday() {
        let (store, disk) = makeStore(initial: "")
        store.load()
        store.park(title: "Wild thought", details: "Maybe.")
        store.saveNow()
        XCTAssertTrue(disk.value.hasPrefix("## Unsorted\n- Wild thought (2026-07-19)\n    Maybe."))
        XCTAssertEqual(store.document.bays[0].name, "Unsorted")
    }

    func testDeleteRemovesIdea() {
        let (store, disk) = makeStore(initial: canonical)
        store.load()
        store.delete(bayIndex: 0, ideaIndex: 0)
        store.saveNow()
        XCTAssertFalse(disk.value.contains("Lock screen widget"))
        XCTAssertEqual(store.ideaCount, 1)
    }

    func testMoveKeepsMetadata() {
        let (store, _) = makeStore(initial: canonical)
        store.load()
        store.move(bayIndex: 0, ideaIndex: 0, toBay: "Hardware")
        let moved = store.document.bays.first { $0.name == "Hardware" }?.ideas.last
        XCTAssertEqual(moved?.title, "Lock screen widget")
        XCTAssertEqual(moved?.parked, "2026-07-19")
        XCTAssertEqual(moved?.color, "yellow")
        XCTAssertEqual(moved?.details, "A tiny glanceable version.")
        XCTAssertTrue(store.document.bays.first { $0.name == "Apps" }!.ideas.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ParkingLotStoreTests`
Expected: compile error, `ParkingLotStore` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/DrawerCore/ParkingLotStore.swift`:

```swift
import Combine
import Foundation

/// The parking lot file: loaded on start, watched for outside edits, and
/// spliced back one idea at a time as you type. There is no save button.
/// Mirrors NotesStore's debounce and FileWatcher wiring.
@MainActor
public final class ParkingLotStore: ObservableObject {
    @Published public private(set) var document = ParkingLotDocument()

    public let fileURL: URL
    private var text = ""
    private let watcher: FileWatcher
    private let debounce: TimeInterval
    private var saveTask: Task<Void, Never>?
    private let readString: (URL) throws -> String
    private let writeString: (String, URL) throws -> Void
    private let todayProvider: () -> String

    public convenience init(fileURL: URL, debounce: TimeInterval = 0.4) {
        self.init(
            fileURL: fileURL,
            debounce: debounce,
            readString: { try String(contentsOf: $0, encoding: .utf8) },
            writeString: { value, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try value.write(to: url, atomically: true, encoding: .utf8)
            },
            todayProvider: TodoStore.localToday
        )
    }

    init(
        fileURL: URL,
        debounce: TimeInterval,
        readString: @escaping (URL) throws -> String,
        writeString: @escaping (String, URL) throws -> Void,
        todayProvider: @escaping () -> String
    ) {
        self.fileURL = fileURL
        self.debounce = max(0, debounce)
        self.readString = readString
        self.writeString = writeString
        self.todayProvider = todayProvider
        self.watcher = FileWatcher(
            directory: fileURL.deletingLastPathComponent(), pollFile: fileURL)
    }

    public func start() {
        watcher.onChange = { [weak self] in self?.load() }
        watcher.start()
        load()
    }

    public func load() {
        let read = (try? readString(fileURL)) ?? ""
        // Our own atomic write comes back through the watcher; skip the noop.
        guard read != text else { return }
        text = read
        document = ParkingLotParser.parse(text)
    }

    public var ideaCount: Int { document.bays.reduce(0) { $0 + $1.ideas.count } }

    public func update(
        bayIndex: Int, ideaIndex: Int, title: String, details: String, color: String?
    ) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        apply(ParkingLotWriteback.replace(
            idea, in: text, title: title, details: details, color: color))
    }

    public func delete(bayIndex: Int, ideaIndex: Int) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        apply(ParkingLotWriteback.delete(idea, in: text))
    }

    /// The only in-app way to move an idea between bays: drop its lines from
    /// the old bay and append them to the new one, metadata intact.
    public func move(bayIndex: Int, ideaIndex: Int, toBay bay: String) {
        guard let idea = idea(bayIndex, ideaIndex) else { return }
        var next = ParkingLotWriteback.delete(idea, in: text)
        next = ParkingLotWriteback.append(
            title: idea.title, details: idea.details,
            parked: idea.parked, color: idea.color, toBay: bay, in: next)
        apply(next)
    }

    /// Capture: appends to the Unsorted bay stamped with today's date.
    public func park(title: String, details: String) {
        apply(ParkingLotWriteback.append(
            title: title, details: details, parked: todayProvider(),
            color: nil, toBay: "Unsorted", in: text))
    }

    /// Writes right now, cancelling any pending debounce. Call on teardown.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? writeString(text, fileURL)
    }

    private func idea(_ bay: Int, _ idea: Int) -> ParkedIdea? {
        guard document.bays.indices.contains(bay),
              document.bays[bay].ideas.indices.contains(idea) else { return nil }
        return document.bays[bay].ideas[idea]
    }

    private func apply(_ newText: String) {
        text = newText
        document = ParkingLotParser.parse(text)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        let delay = debounce
        saveTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            // Best effort, same as NotesStore: the next edit tries again.
            try? self.writeString(snapshot, self.fileURL)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ParkingLotStoreTests`
Expected: 5 tests pass. Then run the full suite once: `swift test`. Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add Sources/DrawerCore/ParkingLotStore.swift Tests/DrawerCoreTests/ParkingLotStoreTests.swift
git commit -m "Add the parking lot store"
```

---

### Task 4: Flag, path, and app wiring

**Files:**
- Modify: `Sources/Drawer/FeatureFlags.swift` (the `FeatureFlag` enum)
- Modify: `Sources/Drawer/AppPaths.swift`
- Modify: `Sources/Drawer/AppDelegate.swift:16-17` (properties), `:113` (setup), `:235-236` (teardown)
- Modify: `Sources/Drawer/DrawerView.swift` (one new property)

**Interfaces:**
- Consumes: `ParkingLotStore` (Task 3), `AppPaths.drawerFile`.
- Produces: `FeatureFlag.parkingLot` (key `feature.parkingLot`, default off), `AppPaths.parkingLotFile: URL`, `AppDelegate.parkingLotStore`, `DrawerView.lot: ParkingLotStore?`. Tasks 5 to 7 read `lot` from `DrawerView` and the flag via `@AppStorage("feature.parkingLot")`.

- [ ] **Step 1: Add the flag case**

In `Sources/Drawer/FeatureFlags.swift`, after `case bureau` add:

```swift
    /// The pinned parking lot board: every loose idea as a car in a stall,
    /// backed by Parking lot.md next to your drawer file. Off by default.
    case parkingLot
```

Add to `title`:

```swift
        case .parkingLot: return "Parking lot"
```

Add to `blurb`:

```swift
        case .parkingLot: return "Loose ideas as cars in a lot, in Parking lot.md next to your drawer file. Off by default; rough edges."
```

Add to `group` (join the `Controls` cases):

```swift
        case .filterMenu, .notes, .ideas, .ideaCapture, .history, .parkingLot: return "Controls"
```

(and remove `.parkingLot` from nowhere else; the old `Controls` line loses nothing.)

Add to the `defaultValue` off-list:

```swift
        case .attribution, .planner, .history, .workMode, .ideaCapture, .bureau, .parkingLot: return false
```

- [ ] **Step 2: Add the file path**

In `Sources/Drawer/AppPaths.swift`, after the `ideasDirectory` computed var add:

```swift
    /// Parking lot.md sits next to the resolved drawer file, so it rides the
    /// same resolution chain and the same vault.
    static var parkingLotFile: URL {
        URL(fileURLWithPath: drawerFile).deletingLastPathComponent()
            .appendingPathComponent("Parking lot.md")
    }
```

- [ ] **Step 3: Wire the store through the app**

In `Sources/Drawer/AppDelegate.swift`:

Near line 17, after `private var boardStore: BoardStore!`:

```swift
    private var parkingLotStore: ParkingLotStore!
```

After `boardStore.load()` (line 113):

```swift
        parkingLotStore = ParkingLotStore(fileURL: AppPaths.parkingLotFile)
        parkingLotStore.start()
```

After the `#endif` of the Bureau block (line ~157), before `controller = PanelController(rootView: rootView)`:

```swift
        rootView.lot = parkingLotStore
```

In `applicationWillTerminate` next to `boardStore?.saveNow()` (line ~236):

```swift
        parkingLotStore?.saveNow() // flush a mid-debounce lot edit
```

In `Sources/Drawer/DrawerView.swift`, next to the existing `ideas` property (search for `ideas: BoardStore`), add a defaulted property so the big memberwise init call in AppDelegate stays untouched:

```swift
    var lot: ParkingLotStore? = nil
```

- [ ] **Step 4: Build and check**

Run: `swift build && swift test`
Expected: clean build, all tests pass. Launch nothing yet; the flag renders a "Parking lot" toggle under Settings > Features > Controls and that is all.

- [ ] **Step 5: Commit**

```bash
git add Sources/Drawer/FeatureFlags.swift Sources/Drawer/AppPaths.swift Sources/Drawer/AppDelegate.swift Sources/Drawer/DrawerView.swift
git commit -m "Put the parking lot behind a setting"
```

Note: `DrawerView.swift` has pre-existing uncommitted changes. If they are still present, stage only your hunk with `git add -p Sources/Drawer/DrawerView.swift`, or get the user to commit their work first (preferred; flag it).

---

### Task 5: The lot renders

**Files:**
- Create: `Sources/Drawer/CarSprite.swift`
- Create: `Sources/Drawer/ParkingLotView.swift`
- Modify: `Sources/Drawer/IdeaBoardPage.swift` (mount the lot, pin the selector row)
- Modify: `Sources/Drawer/DrawerView.swift:269` (pass `lot` into `IdeaBoardPage`)

**Interfaces:**
- Consumes: `ParkingLotStore` (`document`, `ideaCount`), `ParkingLotLayout.columns`, `Palette.card(_:).color`, `DrawerView.lot` (Task 4).
- Produces: `CarSprite(color: Color)` (a View; 300x128 design space, nose faces right), `ParkingLotView(lot: ParkingLotStore)` (a View), and inside it `ParkingLotView.IdeaRef` (`bay: Int`, `idea: Int`, Hashable) which Task 6 extends with selection. `IdeaBoardPage` gains `var lot: ParkingLotStore? = nil` and `@AppStorage("boardShowingParkingLot") private var showingLot = false`.

- [ ] **Step 1: Write the car sprite**

Create `Sources/Drawer/CarSprite.swift`. This is the sedan from the agreed mockup (`gta-cars.html`), translated from its 300x128 SVG: flat paint, hard outline, raked glass, wheels poking out at the corners, headlights right, red tails left. The car carries no text.

```swift
import SwiftUI

/// A top-down car in the old GTA style. Draws in a 300x128 design space
/// scaled to fit. Colour is the flat body paint; everything else is fixed.
/// Nose faces right; mirror with scaleEffect(x: -1) to face left.
struct CarSprite: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 300
            let sy = size.height / 128
            let s = min(sx, sy)
            func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy),
                     cornerRadius: r * s)
            }
            func poly(_ pts: [(Double, Double)]) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: pts[0].0 * sx, y: pts[0].1 * sy))
                for pt in pts.dropFirst() {
                    p.addLine(to: CGPoint(x: pt.0 * sx, y: pt.1 * sy))
                }
                p.closeSubpath()
                return p
            }
            let outline = Color(red: 0.055, green: 0.055, blue: 0.07)
            let glass = Color(red: 0.10, green: 0.145, blue: 0.19)
            let tyre = Color(red: 0.078, green: 0.078, blue: 0.094)

            // Wheels first, so the body sits on top of them.
            for (x, y) in [(54.0, 8.0), (196, 8), (54, 106), (196, 106)] {
                ctx.fill(box(x, y, 46, 14, 2), with: .color(tyre))
            }
            let bodyPath = box(8, 17, 284, 94, 22)
            ctx.fill(bodyPath, with: .color(color))
            ctx.stroke(bodyPath, with: .color(outline), lineWidth: 3 * s)
            // A light band along the top edge sells the roof curve.
            ctx.fill(box(14, 20, 272, 26, 14), with: .color(.white.opacity(0.08)))
            // Raked glass, front then rear.
            let windshield = poly([(198, 30), (222, 44), (222, 84), (198, 98)])
            ctx.fill(windshield, with: .color(glass))
            ctx.stroke(windshield, with: .color(outline), lineWidth: 2.5 * s)
            let rear = poly([(96, 30), (76, 44), (76, 84), (96, 98)])
            ctx.fill(rear, with: .color(glass))
            ctx.stroke(rear, with: .color(outline), lineWidth: 2.5 * s)
            // Roof shade between the glass.
            ctx.fill(box(96, 26, 102, 76, 6), with: .color(.black.opacity(0.07)))
            // Headlights at the nose, red tails at the tail.
            let lamp = Color(red: 1.0, green: 0.933, blue: 0.706)
            let tail = Color(red: 0.788, green: 0.208, blue: 0.173)
            ctx.fill(box(270, 30, 16, 13, 3), with: .color(lamp))
            ctx.fill(box(270, 85, 16, 13, 3), with: .color(lamp))
            ctx.fill(box(12, 30, 12, 13, 3), with: .color(tail))
            ctx.fill(box(12, 85, 12, 13, 3), with: .color(tail))
            // Wing mirrors.
            ctx.fill(box(196, 22, 9, 7, 2), with: .color(outline))
            ctx.fill(box(196, 99, 9, 7, 2), with: .color(outline))
        }
        .aspectRatio(300.0 / 128.0, contentMode: .fit)
    }
}
```

- [ ] **Step 2: Write the lot view (render only, no interaction yet)**

Create `Sources/Drawer/ParkingLotView.swift`:

```swift
import DrawerCore
import SwiftUI

/// The lot: bays from the markdown as blocks of painted stalls, one car per
/// stall in file order. A bay overflows into the next block right; blocks
/// alternate the way they nose in so each faces the bare gap on its own side.
/// There is no road. Zoom magnifies, nothing else.
struct ParkingLotView: View {
    @ObservedObject var lot: ParkingLotStore

    @State private var zoom: CGFloat = 1
    @State private var gestureZoom: CGFloat = 1
    @Namespace private var carSpace

    struct IdeaRef: Hashable {
        var bay: Int
        var idea: Int
    }

    private let stallWidth: CGFloat = 168
    private let stallHeight: CGFloat = 108
    private let gapWidth: CGFloat = 56
    private let asphalt = Color(red: 0.165, green: 0.165, blue: 0.18)
    private let paint = Color.white.opacity(0.16)
    private let stencilInk = Color.white.opacity(0.5)

    private struct Block: Identifiable {
        var id: Int
        var bay: Int
        var range: Range<Int>
        var showsLabel: Bool
        /// Odd blocks mirror so their cars nose left, into the shared gap.
        var mirrored: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let stallsPerColumn = max(1, Int((geo.size.height - 80) / stallHeight))
            ScrollView([.horizontal, .vertical]) {
                lotBody(stallsPerColumn: stallsPerColumn)
                    .padding(24)
                    .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
            }
            .background(asphalt)
            .gesture(
                MagnifyGesture()
                    .onChanged { gestureZoom = $0.magnification }
                    .onEnded { _ in
                        zoom = min(2.5, max(0.5, zoom * gestureZoom))
                        gestureZoom = 1
                    }
            )
        }
    }

    private func blocks(stallsPerColumn: Int) -> [Block] {
        var out: [Block] = []
        for (b, bay) in lot.document.bays.enumerated() {
            let cols = ParkingLotLayout.columns(bay.ideas.count, stallsPerColumn: stallsPerColumn)
            for (i, range) in cols.enumerated() {
                out.append(Block(
                    id: out.count, bay: b, range: range,
                    showsLabel: i == 0, mirrored: out.count % 2 == 1))
            }
        }
        return out
    }

    private func lotBody(stallsPerColumn: Int) -> some View {
        let blocks = blocks(stallsPerColumn: stallsPerColumn)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(blocks) { block in
                blockView(block)
                gapView(index: block.id)
            }
        }
    }

    private func blockView(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.showsLabel ? lot.document.bays[block.bay].name.uppercased() : " ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 18)
                .padding(.bottom, 8)
            ForEach(block.range, id: \.self) { i in
                stall(bay: block.bay, idea: i, mirrored: block.mirrored)
            }
        }
    }

    private func stall(bay: Int, idea: Int, mirrored: Bool) -> some View {
        let ref = IdeaRef(bay: bay, idea: idea)
        let parked = lot.document.bays[bay].ideas[idea]
        return VStack(spacing: 5) {
            CarSprite(color: Palette.card(parked.color).color)
                .frame(width: stallWidth - 28)
                .scaleEffect(x: mirrored ? -1 : 1)
                .matchedGeometryEffect(id: ref, in: carSpace)
            Text(parked.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 28)
        }
        .frame(width: stallWidth, height: stallHeight)
        .overlay(stallLines(mirrored: mirrored))
    }

    /// Painted stall lines: top, bottom, and the closed end. The open end
    /// faces the gap the car noses into.
    private func stallLines(mirrored: Bool) -> some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width
                let h = geo.size.height
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: w, y: 0))
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
                let closedX: CGFloat = mirrored ? w : 0
                p.move(to: CGPoint(x: closedX, y: 0))
                p.addLine(to: CGPoint(x: closedX, y: h))
            }
            .stroke(paint, lineWidth: 2)
        }
    }

    private func gapView(index: Int) -> some View {
        Color.clear.frame(width: gapWidth, height: 1)
    }
}
```

- [ ] **Step 3: Mount the lot in the board page and pin the selector row**

In `Sources/Drawer/IdeaBoardPage.swift`:

Add properties to `IdeaBoardPage` (after `var theme: DrawerTheme`):

```swift
    var lot: ParkingLotStore? = nil
```

and with the other `@AppStorage` lines:

```swift
    @AppStorage("feature.parkingLot") private var parkingLotEnabled = false
    @AppStorage("boardShowingParkingLot") private var showingLot = false
```

Add a computed helper below `xpBoard`:

```swift
    private var lotActive: Bool { showingLot && parkingLotEnabled && lot != nil }
```

In `body`, replace the bare `BoardCanvas(...)` call with:

```swift
            if lotActive, let lot {
                ParkingLotView(lot: lot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BoardCanvas(
                    store: store,
                    recenterRequests: recenterRequests,
                    transparentBackground: transparent,
                    globalPanEnabled: swipe.showingBoard,
                    paperBackground: paper,
                    xpBackground: xpBoard
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
```

In `header`, wrap the board-only buttons (undo, redo, both zoom buttons, recenter, background) in `if !lotActive { ... }`, and change the trailing count `Text` to:

```swift
            Text(lotActive ? "\(lot?.ideaCount ?? 0)" : "\(store.document.items.count)")
```

In `boardSelector`, change the label text to:

```swift
                Text(lotActive ? "Parking lot" : store.activeBoardName)
```

and pass the new state into the popover:

```swift
        .popover(isPresented: $showingBoardSelector, arrowEdge: .bottom) {
            BoardSelectorPopover(
                store: store,
                lot: parkingLotEnabled ? lot : nil,
                showingLot: $showingLot,
                isPresented: $showingBoardSelector
            )
            .environment(\.drawerTheme, theme)
        }
```

In `BoardSelectorPopover`, add the two new properties after `store`:

```swift
    var lot: ParkingLotStore?
    @Binding var showingLot: Bool
```

At the top of its `VStack(spacing: 0)`, before the `List`, add the pinned row. It has no swipe actions: the lot cannot be renamed or deleted.

```swift
            if let lot {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(showingLot ? 1 : 0)
                        .frame(width: 14)
                    Image(systemName: "car.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Parking lot")
                        .font(theme.uiFont(size: 13, weight: showingLot ? .semibold : .regular))
                    Spacer()
                    Text("\(lot.ideaCount)")
                        .font(theme.uiFont(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingLot = true
                    isPresented = false
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Parking lot, \(lot.ideaCount) ideas")
                .accessibilityAddTraits(showingLot ? [.isButton, .isSelected] : .isButton)
                Divider()
            }
```

In the board row's `.onTapGesture`, add `showingLot = false` before `isPresented = false`. In `BoardSelectorRow`'s call site, pass selection as `selected: board.id == store.document.activeBoardID && !showingLot`.

In `Sources/Drawer/DrawerView.swift` line 269, pass the lot through:

```swift
                IdeaBoardPage(store: ideas, theme: theme, lot: lot) {
                    swipe.showingBoard = false
                }
```

(SwiftUI memberwise init: `lot` is declared after `theme` with a default, and `onBack` is the trailing closure, so this labels line up; adjust label order to match the declaration order if the compiler complains.)

- [ ] **Step 4: Build and verify by hand**

Run: `swift build && swift test` (expected: green), then `make app && make install`, quit and reopen Drawer.

Check: Settings > Features > Controls > turn on "Parking lot". Open the idea board, click the board selector; "Parking lot" sits pinned at the top with a car icon and no swipe actions. Select it: bays from `Parking lot.md` render as blocks of stalls with cars and stencilled titles, alternate blocks mirrored, bare asphalt gaps, no road. Pinch zooms. If the file does not exist yet, the lot is empty; create it with the Task 1 test fixture content to see cars.

- [ ] **Step 5: Commit**

```bash
git add Sources/Drawer/CarSprite.swift Sources/Drawer/ParkingLotView.swift Sources/Drawer/IdeaBoardPage.swift
git add -p Sources/Drawer/DrawerView.swift
git commit -m "Show ideas as cars in a parking lot"
```

---

### Task 6: Pull a car out and edit it

**Files:**
- Modify: `Sources/Drawer/ParkingLotView.swift`

**Interfaces:**
- Consumes: `ParkingLotStore.update/delete/move/saveNow`, `IdeaRef`, `carSpace` namespace (Task 5).
- Produces: press-to-pull-out selection, the `IdeaPanel` editor. Nothing downstream consumes these; this is the leaf.

- [ ] **Step 1: Add selection state and the widening gap**

In `ParkingLotView`, add state:

```swift
    @State private var selected: IdeaRef?
```

and a constant next to `gapWidth`:

```swift
    private let openGapWidth: CGFloat = 300
```

Replace `lotBody` with a version that knows which gap is open. A car from an even block noses right into its own gap; a mirrored block noses left into the previous one, so facing blocks share a gap, which is the design.

```swift
    private func lotBody(stallsPerColumn: Int) -> some View {
        let blocks = blocks(stallsPerColumn: stallsPerColumn)
        let openGap = selectedGapIndex(in: blocks)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(blocks) { block in
                blockView(block)
                gapView(index: block.id, open: openGap == block.id, blocks: blocks)
            }
        }
        .animation(.easeOut(duration: 0.3), value: selected)
        .onExitCommand { close() }
    }

    private func blockContaining(_ ref: IdeaRef, in blocks: [Block]) -> Block? {
        blocks.first { $0.bay == ref.bay && $0.range.contains(ref.idea) }
    }

    private func selectedGapIndex(in blocks: [Block]) -> Int? {
        guard let sel = selected, let block = blockContaining(sel, in: blocks) else { return nil }
        return block.mirrored ? block.id - 1 : block.id
    }
```

Replace `gapView` with:

```swift
    private func gapView(index: Int, open: Bool, blocks: [Block]) -> some View {
        Group {
            if open, let sel = selected, let parked = idea(sel),
               let block = blockContaining(sel, in: blocks) {
                VStack(alignment: .leading, spacing: 10) {
                    CarSprite(color: Palette.card(parked.color).color)
                        .frame(width: 190)
                        .scaleEffect(x: block.mirrored ? -1 : 1)
                        .matchedGeometryEffect(id: sel, in: carSpace)
                        .onTapGesture { close() }
                    IdeaPanel(lot: lot, bay: sel.bay, idea: sel.idea) { target in
                        moveSelected(toBay: target)
                    }
                    .id(sel)
                    .frame(width: 264)
                }
                .padding(.top, 26 + CGFloat(sel.idea - block.range.lowerBound) * stallHeight)
                .padding(.horizontal, 18)
                .frame(width: openGapWidth, alignment: .topLeading)
            } else {
                Color.clear.frame(width: gapWidth, height: 1)
            }
        }
    }

    private func idea(_ ref: IdeaRef) -> ParkedIdea? {
        guard lot.document.bays.indices.contains(ref.bay),
              lot.document.bays[ref.bay].ideas.indices.contains(ref.idea) else { return nil }
        return lot.document.bays[ref.bay].ideas[ref.idea]
    }
```

- [ ] **Step 2: Make the stall react**

Replace `stall(bay:idea:mirrored:)` so a pressed car leaves its stall (the stencil stays, marking whose space is empty) and pressing a parked car selects it:

```swift
    private func stall(bay: Int, idea: Int, mirrored: Bool) -> some View {
        let ref = IdeaRef(bay: bay, idea: idea)
        let parked = lot.document.bays[bay].ideas[idea]
        let out = selected == ref
        return VStack(spacing: 5) {
            if out {
                // The car is out in the gap; keep its footprint.
                Color.clear
                    .frame(width: stallWidth - 28, height: (stallWidth - 28) * 128 / 300)
            } else {
                CarSprite(color: Palette.card(parked.color).color)
                    .frame(width: stallWidth - 28)
                    .scaleEffect(x: mirrored ? -1 : 1)
                    .matchedGeometryEffect(id: ref, in: carSpace)
                    .onTapGesture { toggle(ref) }
            }
            Text(parked.title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(stencilInk.opacity(out ? 0.6 : 1))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: stallWidth - 28)
        }
        .frame(width: stallWidth, height: stallHeight)
        .overlay(stallLines(mirrored: mirrored))
    }
```

- [ ] **Step 3: Selection plumbing**

Add to `ParkingLotView`:

```swift
    private func toggle(_ ref: IdeaRef) {
        if selected == ref {
            close()
        } else {
            if selected != nil { close() }
            selected = ref
        }
    }

    /// Reverses the car back in. An idea cleared to nothing is removed, no
    /// confirmation: closing an empty panel is the delete gesture.
    private func close() {
        guard let sel = selected else { return }
        if let parked = idea(sel), parked.title.isEmpty, parked.details.isEmpty {
            lot.delete(bayIndex: sel.bay, ideaIndex: sel.idea)
        }
        lot.saveNow()
        selected = nil
    }

    private func moveSelected(toBay target: String) {
        guard let sel = selected else { return }
        lot.move(bayIndex: sel.bay, ideaIndex: sel.idea, toBay: target)
        if let b = lot.document.bays.firstIndex(where: { $0.name == target }),
           !lot.document.bays[b].ideas.isEmpty {
            selected = IdeaRef(bay: b, idea: lot.document.bays[b].ideas.count - 1)
        } else {
            selected = nil
        }
    }
```

- [ ] **Step 4: The panel**

Add to the bottom of `ParkingLotView.swift`:

```swift
/// The pulled-out idea. The panel is the markdown, not a form: the first line
/// is the title, the rest is the details. No save button; edits splice back
/// through the store's debounce. The caret lands on open.
private struct IdeaPanel: View {
    @ObservedObject var lot: ParkingLotStore
    let bay: Int
    let idea: Int
    var onMoveToBay: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(lot: ParkingLotStore, bay: Int, idea: Int, onMoveToBay: @escaping (String) -> Void) {
        self._lot = ObservedObject(wrappedValue: lot)
        self.bay = bay
        self.idea = idea
        self.onMoveToBay = onMoveToBay
        let parked = lot.document.bays[bay].ideas[idea]
        self._draft = State(initialValue: parked.details.isEmpty
            ? parked.title
            : parked.title + "\n" + parked.details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaLine
            TextEditor(text: $draft)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 12))
                .frame(minHeight: 90, maxHeight: 220)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(red: 0.957, green: 0.945, blue: 0.91)))
        .foregroundStyle(Color(red: 0.17, green: 0.16, blue: 0.15))
        .shadow(color: .black.opacity(0.45), radius: 7, y: 5)
        .onAppear { focused = true }
        .onChange(of: draft) { _, text in
            let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let color = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].color : nil
            lot.update(
                bayIndex: bay, ideaIndex: idea,
                title: String(parts.first ?? "").trimmingCharacters(in: .whitespaces),
                details: parts.count > 1 ? String(parts[1]) : "",
                color: color)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            if let parked = lot.document.bays.indices.contains(bay)
                && lot.document.bays[bay].ideas.indices.contains(idea)
                ? lot.document.bays[bay].ideas[idea].parked : nil {
                Text("PARKED \(parked)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(lot.document.bays.map(\.name), id: \.self) { name in
                    Button(name) {
                        if name != lot.document.bays[bay].name { onMoveToBay(name) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(lot.document.bays.indices.contains(bay)
                        ? lot.document.bays[bay].name : "")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
```

- [ ] **Step 5: Build and verify by hand**

Run: `swift build && swift test`, then `make app && make install`, quit and reopen.

Check, in order: press a car; it noses out into the gap (mirrored blocks nose left), the gap widens, the panel opens under the car with the caret in the text. The vacated stall keeps its stencil. Type: the first line changes the stencil live; check the file on disk updates after the debounce. Change the bay from the dropdown: the car reappears at the end of the target bay, file rewritten. Press the car again: it reverses back in. Press Escape: same. Select all text, delete it, press Escape: the idea is gone from the lot and the file, no confirmation. Zoom while a car is out: everything just magnifies.

- [ ] **Step 6: Commit**

```bash
git add Sources/Drawer/ParkingLotView.swift
git commit -m "Pull a car out to read and edit its idea"
```

---

### Task 7: Capture parks in the lot file

**Files:**
- Modify: `Sources/Drawer/IdeaCaptureBar.swift:6-12` (property), `:86-101` (`park()`)
- Modify: `Sources/Drawer/DrawerView.swift:568-574` (pass the lot)

**Interfaces:**
- Consumes: `ParkingLotStore.park(title:details:)` (Task 3), `DrawerView.lot` (Task 4).
- Produces: nothing new; behaviour change only.

- [ ] **Step 1: Retarget the Park button**

In `Sources/Drawer/IdeaCaptureBar.swift`, add after `@ObservedObject var store: BoardStore`:

```swift
    /// When set, Park writes to the parking lot file instead of board.json.
    var lot: ParkingLotStore? = nil
```

In `park()`, replace the `store.addText(...)` call with:

```swift
        let title = String(parts.first ?? "")
        let body = parts.count > 1 ? String(parts[1]) : ""
        if let lot {
            lot.park(title: title, details: body)
        } else {
            store.addText(title: title, body: body)
        }
```

- [ ] **Step 2: Pass the lot from DrawerView**

`DrawerView` needs the flag; add with its other `@AppStorage` properties:

```swift
    @AppStorage("feature.parkingLot") private var parkingLotEnabled = false
```

At line 568, change the capture bar construction to:

```swift
                if showingCapture, ideaCaptureEnabled, let ideas {
                    IdeaCaptureBar(
                        store: ideas,
                        lot: parkingLotEnabled ? lot : nil,
                        reduceMotion: reduceMotion
                    ) {
                        showingCapture = false
                    }
                    .padding(.leading, notebookWritingInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
```

- [ ] **Step 3: Build and verify by hand**

Run: `swift build && swift test`, then `make app && make install`, quit and reopen.

Check: with both "Idea capture bar" and "Parking lot" on, jot an idea and press `Park ◂`. The drive-off animation still plays, `board.json` gains nothing, and `Parking lot.md` gains the idea at the end of `## Unsorted` (created at the top of the file if missing) stamped with today's date. With "Parking lot" off, Park still writes to the board as before.

- [ ] **Step 4: Commit**

```bash
git add Sources/Drawer/IdeaCaptureBar.swift
git add -p Sources/Drawer/DrawerView.swift
git commit -m "Send parked ideas to the lot file"
```

---

### Task 8: Ship it

**Files:**
- No new code. Verification, push, and the vault status line.

- [ ] **Step 1: Full check**

Run: `swift build && swift test`
Expected: everything green.

Run: `make app && make install`, quit and reopen Drawer. One pass through the whole flow: toggle on, open lot from selector, press a car, edit, move bay, delete by clearing, capture with Park, hand-edit the file in another editor and watch the lot update.

- [ ] **Step 2: Push**

```bash
git push
```

Report any commits that did not push. Unpushed commits at session end are a bug.

- [ ] **Step 3: Update the vault status line**

Per CLAUDE.md: add one dated line to the Drawer entry in
`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/My life/1 Projects/0 Dashboard.md`
and the `## Status` section of `1 Projects/Drawer.md`, e.g.
`2026-07-19: Parking lot shipped behind a flag, ideas live in Parking lot.md as cars.`
