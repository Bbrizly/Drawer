import Combine
import CoreGraphics
import Foundation

public struct BoardMetrics: Equatable, Sendable {
    public static let smoothLayerBudget = 320
    public static let smoothAreaBudget = 2_000_000

    public var itemCount: Int
    public var textCount: Int
    public var imageCount: Int
    public var jsonBytes: Int
    public var mediaBytes: Int
    public var canvasLayerCount: Int
    public var canvasPointArea: Int

    public var totalBytes: Int { jsonBytes + mediaBytes }

    public var canvasLoadPercent: Int {
        guard itemCount > 0 else { return 0 }
        let layerLoad = Double(canvasLayerCount) / Double(Self.smoothLayerBudget)
        let areaLoad = Double(canvasPointArea) / Double(Self.smoothAreaBudget)
        return min(999, max(1, Int((max(layerLoad, areaLoad) * 100).rounded())))
    }
}

/// Holds the idea board and saves it to `board.json`. Modeled on NotesStore:
/// loads on demand, autosaves with a debounce so a burst of drags is one write,
/// and flushes on teardown via `saveNow`. IO is injected so tests never touch
/// disk. The app is the only writer, so there is no file watcher.
@MainActor
public final class BoardStore: ObservableObject {
    @Published public private(set) var document = BoardDocument()

    public let directory: URL
    public var boardFile: URL { directory.appendingPathComponent("board.json") }
    public var mediaDirectory: URL { directory.appendingPathComponent("media", isDirectory: true) }
    public var activeBoardName: String { document.activeBoard.name }

    private let readData: (URL) throws -> Data
    private let writeData: (Data, URL) throws -> Void
    private let now: () -> Date
    private let debounce: TimeInterval
    private var saveTask: Task<Void, Never>?

    public convenience init(directory: URL, debounce: TimeInterval = 0.4) {
        self.init(
            directory: directory,
            debounce: debounce,
            readData: { try Data(contentsOf: $0) },
            writeData: { data, url in
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
            },
            now: { Date() }
        )
    }

    init(
        directory: URL,
        debounce: TimeInterval,
        readData: @escaping (URL) throws -> Data,
        writeData: @escaping (Data, URL) throws -> Void,
        now: @escaping () -> Date
    ) {
        self.directory = directory
        self.debounce = max(0, debounce)
        self.readData = readData
        self.writeData = writeData
        self.now = now
    }

    /// Reads board.json into memory. A missing or unreadable file leaves an
    /// empty board (best-effort, like the notes scratchpad).
    public func load() {
        guard let data = try? readData(boardFile),
              let doc = try? Self.decoder.decode(BoardDocument.self, from: data)
        else {
            document = BoardDocument()
            return
        }
        document = doc
    }

    /// Write immediately, cancelling any pending debounce. Call on teardown.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        write(document)
    }

    // MARK: mutations

    @discardableResult
    public func addBoard() -> BoardRecord {
        snapshot()
        let board = BoardRecord(name: nextBoardName())
        document.boards.append(board)
        document.activeBoardID = board.id
        scheduleSave()
        return board
    }

    public func selectBoard(_ id: UUID) {
        guard document.activeBoardID != id,
              document.boards.contains(where: { $0.id == id })
        else { return }
        document.activeBoardID = id
        scheduleSave()
    }

    public func removeBoard(_ id: UUID) {
        guard document.boards.count > 1,
              let index = document.boards.firstIndex(where: { $0.id == id })
        else { return }
        snapshot()
        let wasActive = document.activeBoardID == id
        document.boards.remove(at: index)
        if wasActive {
            document.activeBoardID = document.boards[min(index, document.boards.count - 1)].id
        }
        scheduleSave()
    }

    public func renameBoard(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = document.boards.firstIndex(where: { $0.id == id }),
              document.boards[index].name != trimmed
        else { return }
        snapshot()
        document.boards[index].name = trimmed
        scheduleSave()
    }

    public func metrics(for board: BoardRecord) -> BoardMetrics {
        let jsonBytes = (try? Self.encoder.encode(board).count) ?? 0
        let mediaBytes = Set(board.items.compactMap(\.file)).reduce(0) { total, file in
            total + fileSize(directory.appendingPathComponent(file))
        }
        let textCount = board.items.filter { $0.kind == .text }.count
        let imageCount = board.items.filter { $0.kind == .image }.count
        let canvasPointArea = board.items.reduce(0) { total, item in
            total + Int((item.width * item.height).rounded())
        }
        return BoardMetrics(
            itemCount: board.items.count,
            textCount: textCount,
            imageCount: imageCount,
            jsonBytes: jsonBytes,
            mediaBytes: mediaBytes,
            canvasLayerCount: 5 + board.items.count * 2,
            canvasPointArea: canvasPointArea
        )
    }

    @discardableResult
    public func addText(
        title: String, body: String, at point: CGPoint? = nil, color: String? = nil
    ) -> BoardItem {
        snapshot()
        let p = point ?? cascadePoint()
        let item = BoardItem(
            kind: .text,
            x: Double(p.x), y: Double(p.y),
            width: 220, height: 140,
            z: nextZ(), created: now(),
            title: title,
            body: body.isEmpty ? nil : body,
            color: color
        )
        document.items.append(item)
        scheduleSave()
        return item
    }

    @discardableResult
    public func addImage(
        file: String,
        naturalSize: CGSize,
        displaySize: CGSize,
        at point: CGPoint
    ) -> BoardItem {
        snapshot()
        let item = BoardItem(
            kind: .image,
            x: Double(point.x), y: Double(point.y),
            width: Double(displaySize.width), height: Double(displaySize.height),
            z: nextZ(), created: now(),
            file: file,
            naturalWidth: Double(naturalSize.width),
            naturalHeight: Double(naturalSize.height)
        )
        document.items.append(item)
        scheduleSave()
        return item
    }

    public func updateText(_ id: UUID, title: String, body: String) {
        guard let i = index(of: id) else { return }
        snapshot()
        document.items[i].title = title
        document.items[i].body = body.isEmpty ? nil : body
        scheduleSave()
    }

    public func setColor(_ id: UUID, _ color: String?) {
        guard let i = index(of: id) else { return }
        snapshot()
        document.items[i].color = color
        scheduleSave()
    }

    public func setFontSize(_ id: UUID, _ size: Double) {
        guard let i = index(of: id) else { return }
        snapshot()
        document.items[i].fontSize = size
        scheduleSave()
    }

    public func move(_ id: UUID, to point: CGPoint) {
        guard let i = index(of: id) else { return }
        snapshot()
        document.items[i].x = Double(point.x)
        document.items[i].y = Double(point.y)
        scheduleSave()
    }

    /// Move and resize in one undoable step (the grip drag commits here).
    /// `fontSize` is optional and normally nil; text wraps to the box instead.
    public func moveAndResize(_ id: UUID, to rect: CGRect, fontSize: Double? = nil) {
        guard let i = index(of: id) else { return }
        snapshot()
        document.items[i].x = Double(rect.minX)
        document.items[i].y = Double(rect.minY)
        document.items[i].width = Double(rect.width)
        document.items[i].height = Double(rect.height)
        if let fontSize { document.items[i].fontSize = fontSize }
        scheduleSave()
    }

    /// Move several items at once (marquee drag), as a single undo step.
    public func setPositions(_ positions: [UUID: CGPoint]) {
        guard !positions.isEmpty else { return }
        snapshot()
        for (id, p) in positions where index(of: id) != nil {
            let i = index(of: id)!
            document.items[i].x = Double(p.x)
            document.items[i].y = Double(p.y)
        }
        scheduleSave()
    }

    /// Delete several items at once, as a single undo step.
    public func removeMany(_ ids: Set<UUID>) {
        guard ids.contains(where: { index(of: $0) != nil }) else { return }
        snapshot()
        document.items.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    public func bringToFront(_ id: UUID) {
        guard let i = index(of: id) else { return }
        document.items[i].z = nextZ()
        scheduleSave()
    }

    public func remove(_ id: UUID) {
        guard index(of: id) != nil else { return }
        snapshot()
        document.items.removeAll { $0.id == id }
        scheduleSave()
    }

    public func setViewport(_ viewport: BoardViewport) {
        guard document.viewport != viewport else { return }
        document.viewport = viewport
        scheduleSave()
    }

    /// Zoom by `factor`, clamped 0.25...4, keeping the content's center fixed on
    /// screen. Drives the +/- buttons; needs no view size.
    public func zoomBy(_ factor: CGFloat) {
        var vp = document.viewport
        let newZoom = min(4, max(0.25, vp.zoom * Double(factor)))
        let c = contentCenter()
        let screenX = vp.x + c.x * vp.zoom
        let screenY = vp.y + c.y * vp.zoom
        vp.zoom = newZoom
        vp.x = screenX - c.x * newZoom
        vp.y = screenY - c.y * newZoom
        setViewport(vp)
    }

    private func contentCenter() -> (x: Double, y: Double) {
        guard !document.items.isEmpty else { return (0, 0) }
        let minX = document.items.map(\.x).min()!
        let minY = document.items.map(\.y).min()!
        let maxX = document.items.map { $0.x + $0.width }.max()!
        let maxY = document.items.map { $0.y + $0.height }.max()!
        return ((minX + maxX) / 2, (minY + maxY) / 2)
    }

    // MARK: undo / redo

    private var undoStack: [BoardDocument] = []
    private var redoStack: [BoardDocument] = []

    /// Snapshot the document before an edit. Pan/zoom and selection do not call
    /// this, so each undo step is a real edit, not a camera move.
    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        scheduleSave()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        scheduleSave()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: helpers

    private func index(of id: UUID) -> Int? {
        document.items.firstIndex { $0.id == id }
    }

    /// New cards always land above whatever is already on the board.
    private func nextZ() -> Int {
        (document.items.map(\.z).max() ?? 0) + 1
    }

    private func nextBoardName() -> String {
        let names = Set(document.boards.map(\.name))
        var n = 2
        while names.contains("Board \(n)") { n += 1 }
        return "Board \(n)"
    }

    private func fileSize(_ url: URL) -> Int {
        let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return value?.intValue ?? 0
    }

    /// A spot near the current top-left of the view, cascaded a little so
    /// freshly parked ideas do not stack perfectly on top of each other.
    private func cascadePoint() -> CGPoint {
        let step = Double(document.items.count % 6) * 22
        let inset = 40.0 + step
        let v = document.viewport
        return CGPoint(x: (inset - v.x) / v.zoom, y: (inset - v.y) / v.zoom)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = document
        let delay = debounce
        saveTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.write(snapshot)
        }
    }

    private func write(_ doc: BoardDocument) {
        guard let data = try? Self.encoder.encode(doc) else { return }
        try? writeData(data, boardFile)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
