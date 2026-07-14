import Foundation

/// The order and cap logic for live sticky notes, split out as a plain value
/// type so the "cap at twelve, send the oldest home on the thirteenth" rule
/// (spec "Pull-out") is testable without a display or a real `NSPanel`. The
/// `StickyPanelManager` owns one of these and drives the panels off its
/// decisions.
///
/// `order` holds the live receipt ids oldest-first. Re-inserting an id that is
/// already live moves it to the newest slot (it was just interacted with), so
/// it is never the one retired next.
struct StickyRoster: Equatable {
    private(set) var order: [UUID] = []

    var count: Int { order.count }
    var oldest: UUID? { order.first }
    func contains(_ id: UUID) -> Bool { order.contains(id) }

    /// Registers `id` as the newest live sticky. If that pushes the live count
    /// over `cap`, the oldest id is dropped and returned so the caller can send
    /// it home; otherwise `nil`. `cap` is passed per call (not stored) so a
    /// hot-reload of `sticky.liveCap` takes effect on the very next spawn.
    @discardableResult
    mutating func insert(_ id: UUID, cap: Int) -> UUID? {
        order.removeAll { $0 == id }
        order.append(id)
        guard order.count > max(1, cap) else { return nil }
        return order.removeFirst()
    }

    mutating func remove(_ id: UUID) {
        order.removeAll { $0 == id }
    }
}
