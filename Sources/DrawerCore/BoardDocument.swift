import Foundation

/// Where the board is panned and zoomed to. Saved so reopening the board lands
/// you back where you were.
public struct BoardViewport: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var zoom: Double

    public init(x: Double = 0, y: Double = 0, zoom: Double = 1) {
        self.x = x
        self.y = y
        self.zoom = zoom
    }
}

public struct BoardRecord: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var viewport: BoardViewport
    public var items: [BoardItem]

    public init(
        id: UUID = UUID(),
        name: String,
        viewport: BoardViewport = BoardViewport(),
        items: [BoardItem] = []
    ) {
        self.id = id
        self.name = name
        self.viewport = viewport
        self.items = items
    }
}

/// The board data on disk. Version 1 stored one board as top-level
/// `items`/`viewport`; version 2 stores a small list and keeps computed
/// `items`/`viewport` accessors for the active board.
public struct BoardDocument: Equatable, Sendable {
    public var version: Int
    public var activeBoardID: UUID
    public var boards: [BoardRecord]

    public init(
        version: Int = 2,
        activeBoardID: UUID? = nil,
        boards: [BoardRecord]? = nil,
        viewport: BoardViewport = BoardViewport(),
        items: [BoardItem] = []
    ) {
        let initialBoards: [BoardRecord]
        if let boards, !boards.isEmpty {
            initialBoards = boards
        } else {
            initialBoards = [BoardRecord(name: "Ideas", viewport: viewport, items: items)]
        }
        self.version = version
        self.boards = initialBoards
        let selected = activeBoardID ?? initialBoards[0].id
        self.activeBoardID = initialBoards.contains { $0.id == selected }
            ? selected
            : initialBoards[0].id
    }

    public var activeBoard: BoardRecord {
        get { boards[activeIndex] }
        set {
            boards[activeIndex] = newValue
            activeBoardID = newValue.id
        }
    }

    public var items: [BoardItem] {
        get { activeBoard.items }
        set { boards[activeIndex].items = newValue }
    }

    public var viewport: BoardViewport {
        get { activeBoard.viewport }
        set { boards[activeIndex].viewport = newValue }
    }

    private var activeIndex: Int {
        boards.firstIndex { $0.id == activeBoardID } ?? 0
    }
}

extension BoardDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case version
        case activeBoardID
        case boards
        case viewport
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let boards = try container.decodeIfPresent([BoardRecord].self, forKey: .boards),
           !boards.isEmpty {
            self.init(
                version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 2,
                activeBoardID: try container.decodeIfPresent(UUID.self, forKey: .activeBoardID),
                boards: boards
            )
            return
        }

        self.init(
            version: 2,
            viewport: try container.decodeIfPresent(BoardViewport.self, forKey: .viewport) ?? BoardViewport(),
            items: try container.decodeIfPresent([BoardItem].self, forKey: .items) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(activeBoardID, forKey: .activeBoardID)
        try container.encode(boards, forKey: .boards)
    }
}
