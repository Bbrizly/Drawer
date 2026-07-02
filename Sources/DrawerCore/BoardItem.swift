import CoreGraphics
import Foundation

/// One thing parked on the idea board: a text sticky or an image. Flat and
/// Codable on purpose so board.json stays readable and editable by hand or by
/// an AI, the same promise the tasks file keeps.
public struct BoardItem: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, image }

    public var id: UUID
    public var kind: Kind

    // Board-space rect. Origin is the item's bottom-left corner.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// Stacking order. Higher draws in front.
    public var z: Int
    public var created: Date

    // kind == .text
    public var title: String?
    public var body: String?
    /// Named color key that tints the text ("yellow","pink",...); nil = the
    /// surface-adaptive default. Text only.
    public var color: String?
    /// Title point size for text items; nil = the default (15). Set by dragging
    /// the resize grip. Body text derives from it.
    public var fontSize: Double?

    // kind == .image. `file` is relative to the Ideas/ folder (e.g. "media/x.png").
    public var file: String?
    public var naturalWidth: Double?
    public var naturalHeight: Double?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        z: Int,
        created: Date = Date(),
        title: String? = nil,
        body: String? = nil,
        color: String? = nil,
        fontSize: Double? = nil,
        file: String? = nil,
        naturalWidth: Double? = nil,
        naturalHeight: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.z = z
        self.created = created
        self.title = title
        self.body = body
        self.color = color
        self.fontSize = fontSize
        self.file = file
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
    }

    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
