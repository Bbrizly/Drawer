import DrawerCore
import Foundation

/// Where a receipt sits in the drawer, normalized coordinates the scene maps
/// to its own space. Plain `Double`s (not `CGPoint`) so this target stays
/// Foundation-only, matching `DrawerCore`'s dependency-free style.
public struct ReceiptPosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Where a receipt is in its life cycle. See `bureau-spec.md` "The drawer
/// scene" and "The stamp" for what each state looks like on screen.
public enum ReceiptState: String, Codable, Equatable, Sendable {
    case queued
    case inDrawer
    case sticky
    case filed
    case expired
}

/// Sticky note size, cycled by double-click per `bureau-spec.md` "Pull-out".
public enum StickySize: String, Codable, Equatable, Sendable {
    case full
    case title
    case chip
}

/// A printed receipt's durable state: which task it is, where it sits, and
/// how it looks. Identity is `id` (a `UUID`) plus the `textSnapshot` /
/// `sectionDate` / `occurrence` triple that lets a receipt re-find its live
/// `TodoItem` after Drawer.md changes underneath it (rename, resection,
/// reorder). `Drawer.md` stays the single source of truth; this is only a
/// view of it, so losing the link just fades the receipt to `.expired`
/// rather than losing any task data.
public struct ReceiptLink: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// The task title at print time (or at last successful re-link). Never
    /// the live title directly; `relink(against:)` refreshes it.
    public var textSnapshot: String
    public var sectionDate: String
    public var occurrence: Int
    public var state: ReceiptState
    public var position: ReceiptPosition
    public var rotation: Double
    public var stickySize: StickySize
    public var createdAt: Date
    public var printedAt: Date?

    public init(
        id: UUID = UUID(),
        textSnapshot: String,
        sectionDate: String,
        occurrence: Int = 0,
        state: ReceiptState = .queued,
        position: ReceiptPosition = ReceiptPosition(x: 0, y: 0),
        rotation: Double = 0,
        stickySize: StickySize = .full,
        createdAt: Date = Date(),
        printedAt: Date? = nil
    ) {
        self.id = id
        self.textSnapshot = textSnapshot
        self.sectionDate = sectionDate
        self.occurrence = occurrence
        self.state = state
        self.position = position
        self.rotation = rotation
        self.stickySize = stickySize
        self.createdAt = createdAt
        self.printedAt = printedAt
    }
}

extension ReceiptLink {
    /// How aged this slip's paper looks (R5): 0 fresh off the printer, 1
    /// after two weeks in the drawer. Reads `printedAt` (falling back to
    /// `createdAt`) so old business visibly yellows in the pile.
    public func ageFactor(now: Date = Date()) -> Double {
        let born = printedAt ?? createdAt
        let days = now.timeIntervalSince(born) / 86_400
        return min(1, max(0, days / 14))
    }

    /// Overlap score below which a title "match" is coincidence, not
    /// confidence the same task moved. Set higher than the 0.5 bar the
    /// attribution classifier uses for its own TitleSimilarity match (spec
    /// risk #4): a false positive here silently re-links a receipt to the
    /// wrong task, which is worse than an occasional orphan.
    public static let relinkThreshold = 0.6

    /// Reattaches this receipt to a live task by title similarity, choosing
    /// the best-scoring candidate in `items`. A match refreshes
    /// `textSnapshot` (titles drift) and leaves `state` untouched. No
    /// candidate clearing `relinkThreshold` orphans the receipt: `state`
    /// becomes `.expired`, whatever it was before, and `nil` is returned.
    @discardableResult
    public mutating func relink(against items: [TodoItem]) -> TodoItem? {
        let scored = items.map { ($0, TitleSimilarity.score(textSnapshot, $0.title)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= Self.relinkThreshold else {
            state = .expired
            return nil
        }
        textSnapshot = best.0.title
        return best.0
    }
}
