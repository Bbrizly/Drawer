import AppKit

/// The non-visual half of the task-completion celebration: a firm trackpad
/// haptic ("boom") and the completion chime. The confetti is a SwiftUI concern
/// (`ConfettiBurst`), kept separate so `TaskRowView` stays AppKit-free.
enum Celebration {
    /// Fire the tactile + audible feedback. Call only when a task goes
    /// undone -> done and celebrations are enabled.
    @MainActor
    static func fire(sound: Bool) {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange, performanceTime: .now
        )
        if sound {
            let id = UserDefaults.standard.string(forKey: "checkOffSound")
                ?? CheckOffSound.chimeID
            let volume = UserDefaults.standard.object(forKey: "checkOffSoundVolume")
                as? Double ?? 0.8
            CheckOffSoundPlayer.shared.play(id: id, volume: volume)
        }
    }
}
