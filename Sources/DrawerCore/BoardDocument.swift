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

/// The whole board on disk: the items plus the viewport. This is exactly what
/// `board.json` encodes.
public struct BoardDocument: Equatable, Codable, Sendable {
    public var version: Int
    public var viewport: BoardViewport
    public var items: [BoardItem]

    public init(
        version: Int = 1,
        viewport: BoardViewport = BoardViewport(),
        items: [BoardItem] = []
    ) {
        self.version = version
        self.viewport = viewport
        self.items = items
    }
}
