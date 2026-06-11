import AppKit

/// The non-visual half of the task-completion celebration: a firm trackpad
/// haptic ("boom") and a short pop. The confetti is a SwiftUI concern
/// (`ConfettiBurst`), kept separate so `TaskRowView` stays AppKit-free.
enum Celebration {
    // One shared player so rapid check-offs don't spawn an NSSound per tap.
    private static let pop: NSSound? = NSSound(named: "Pop")

    /// Fire the tactile + audible feedback. Call only when a task goes
    /// undone -> done and celebrations are enabled.
    @MainActor
    static func fire(sound: Bool) {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange, performanceTime: .now
        )
        if sound, let pop {
            pop.stop() // restart cleanly if it's still ringing from a fast prior tap
            pop.play()
        }
    }
}
