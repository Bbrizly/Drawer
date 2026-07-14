import Foundation

/// Every user-facing string the Bureau feature shows, in one place so later
/// phases (R2-R5) never hand-roll copy inline. Nothing here is wired to a
/// view yet; R1a only lays the data layer.
public enum BureauCopy {
    /// Right-click row action (spec Decision 1).
    public static let queueMenuItem = "Queue for Bureau"
    public static let unqueueMenuItem = "Remove from Bureau"

    /// Top-strip mode button (spec "Layout and mode switch").
    public static let modeButtonTooltip = "Open the Bureau"
    public static let exitModeButtonTooltip = "Back to list"

    /// Stamp labels (spec "The stamp"). The kinds stay done/postponed inside;
    /// the wording follows the Papers-Please stamp rack.
    public static let doneStampLabel = "APPROVED"
    public static let postponedStampLabel = "DENIED"

    /// Slip states shown on a receipt (spec "Architecture", "The drawer scene").
    public static let expiredLabel = "EXPIRED"
    public static let filedLabel = "FILED"

    /// The shredder slot in the bottom-right of the drawer: drop a slip in to
    /// delete just the receipt, never the task.
    public static let shredderLabel = "SHRED"

    /// FILED tray lifetime counter (spec Decision 4).
    public static func lifetimeFiledCaption(_ count: Int) -> String {
        count == 1 ? "1 filed" : "\(count) filed"
    }

    /// Sticky note size-cycle affordance hint (spec "Pull-out").
    public static let stickySizeCycleHint = "Double-click to resize"

    /// "+N more" when subtasks overflow the visible cap (spec Decision 2).
    public static func subtasksOverflow(_ count: Int) -> String {
        "+\(count) more"
    }

    /// The empty add row at the bottom of a full sticky (R3).
    public static let addSubtaskPlaceholder = "Add a subtask"
}
