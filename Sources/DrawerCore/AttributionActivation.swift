import Foundation

/// What the attribution sampler should do, derived purely from Work Mode state.
/// Attribution rides Work Mode: it watches only while Work Mode is on and no task
/// is being hand-tracked. Hand-tracking a task means you have said exactly what
/// you are doing, so the watcher stands down and never competes with your manual
/// clock. Pure and total so the wiring is unit-testable with no AppKit.
public enum AttributionActivation: Equatable, Sendable {
    /// Work Mode on, nothing hand-tracked: sample the frontmost app.
    case observe
    /// Hand-tracking a task, or the feature is not permitted: stop sampling, but
    /// the work session is still open, so no end-of-day summary.
    case suspend
    /// Work Mode off and attribution permitted: stop sampling and write the
    /// day's summary. When not permitted, off suspends instead (no summary).
    case endSession
}

public func attributionActivation(
    workPhase: WorkClock.Phase, permitted: Bool
) -> AttributionActivation {
    switch workPhase {
    // Not permitted means the user disabled automatic attribution, so ending
    // Work Mode must not write an AI day summary.
    case .off:     return permitted ? .endSession : .suspend
    case .running: return .suspend                 // a task is being hand-tracked
    case .paused:  return permitted ? .observe : .suspend
    }
}
