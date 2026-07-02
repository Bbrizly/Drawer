import CoreGraphics
import Foundation

/// Pure conversions between board space and view space, kept out of the canvas
/// so the math can be unit-tested without an NSView. The canvas applies the
/// same transform on its content layer.
///
/// view = board * zoom + pan      board = (view - pan) / zoom
public enum BoardGeometry {
    public static func toBoard(_ p: CGPoint, viewport v: BoardViewport) -> CGPoint {
        CGPoint(x: (p.x - v.x) / v.zoom, y: (p.y - v.y) / v.zoom)
    }

    public static func toView(_ p: CGPoint, viewport v: BoardViewport) -> CGPoint {
        CGPoint(x: p.x * v.zoom + v.x, y: p.y * v.zoom + v.y)
    }

    /// The id of the topmost item (highest z) whose frame contains the board
    /// point, or nil over empty space.
    public static func hitTest(_ board: CGPoint, items: [BoardItem]) -> UUID? {
        var best: BoardItem?
        for item in items where item.frame.contains(board) {
            if best == nil || item.z > best!.z { best = item }
        }
        return best?.id
    }
}
