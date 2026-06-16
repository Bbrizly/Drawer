import Foundation

/// The reading position for the teleprompter. Pure value type so the scroll
/// math is testable on its own. The view feeds it the measured content and
/// viewport heights, then advances it each frame by the elapsed time.
public struct TeleprompterScroll {
    /// How far the text has scrolled up, in points.
    public var offset: Double = 0
    /// Scroll rate in points per second.
    public var speed: Double
    public var contentHeight: Double = 0
    public var viewportHeight: Double = 0

    public init(speed: Double) {
        self.speed = speed
    }

    /// The furthest the text can scroll: the end resting at the viewport edge.
    /// Zero when the text already fits, so short notes never scroll.
    public var maxOffset: Double {
        max(0, contentHeight - viewportHeight)
    }

    public var atEnd: Bool {
        offset >= maxOffset
    }

    /// Advances by `speed * dt`, clamped so it never overshoots the end.
    public mutating func tick(_ dt: Double) {
        guard dt > 0 else { return }
        offset = min(maxOffset, offset + speed * dt)
    }

    public mutating func restart() {
        offset = 0
    }
}
