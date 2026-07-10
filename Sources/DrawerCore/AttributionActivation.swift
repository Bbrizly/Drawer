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

/// What the Work Mode header pill should read. The pill used to derive its state
/// from the clock phase alone, so a paused clock always said "Paused", even when
/// automatic detection was actively watching the frontmost app (no task
/// hand-tracked). That reads as "nothing is happening" while the sampler runs.
public enum WorkHeaderState: Equatable, Sendable {
    /// A task is being hand-tracked: show its running total, offer pause.
    case working
    /// A hand-tracked task was paused by hand: show its total, offer resume.
    case paused
    /// No task hand-tracked and automatic detection is watching the frontmost
    /// app: show what is being watched, not a stalled "Paused".
    case watching
    /// No task and nothing watching: prompt to tap a task to start.
    case idle
}

/// Pure so the pill's state is unit-testable with no SwiftUI. `hasTask` is true
/// once a task has been hand-tracked this session (its id is still the live
/// pointer); `observing` is the sampler's live state.
public func workHeaderState(
    phase: WorkClock.Phase, hasTask: Bool, observing: Bool
) -> WorkHeaderState {
    switch phase {
    case .running: return .working
    case .paused:  return hasTask ? .paused : (observing ? .watching : .idle)
    case .off:     return .idle   // header is hidden while off; total for the switch
    }
}
