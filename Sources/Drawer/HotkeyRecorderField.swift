import AppKit
import SwiftUI

/// The click-and-press shortcut recorder. One field, shared by the onboarding
/// walkthrough and by Settings so the two never drift. Click it to listen,
/// press the keys you want, Esc keeps the old one. While recording it shows the
/// live modifiers with a placeholder cap; when `liveHighlight` is on it also
/// lights each cap under your finger and reports a good press through
/// `onGoodPress` (the walkthrough uses that to rattle its mark).
struct HotkeyRecorderField: View {
    @Environment(\.drawerTheme) private var theme

    /// The current shortcut. The parent owns it so it can persist however it
    /// likes: the walkthrough saves straight to defaults, Settings routes
    /// through its accept-or-revert path.
    @Binding var binding: HotkeyBinding
    /// Accessibility trust, for the status line.
    var trusted: Bool = true
    /// Drives the green confirmed look. The walkthrough sets it once the
    /// shortcut has been tried.
    var confirmed: Bool = false
    /// Watch keys live even when not recording, to preview presses and report
    /// them. Off in Settings, where a press just opens the real drawer.
    var liveHighlight: Bool = false
    /// Swallow a matching press instead of letting it through. On during
    /// onboarding, where the drawer it would open is not built yet.
    var suppressMatchingPress: Bool = false
    /// Show the try/done/accessibility lines under the field. Settings keeps its
    /// own richer captions, so it leaves this off.
    var showStatus: Bool = false
    /// Called with a chosen shortcut once it captures cleanly. The parent
    /// persists it and updates `binding`.
    var onCommit: (HotkeyBinding) -> Void
    /// Called on a good live press (the walkthrough try-it). Nil elsewhere.
    var onGoodPress: (() -> Void)?

    /// True while the whole shortcut is physically down, so the field lights up.
    @State private var held = false
    /// The modifiers down this instant. With `keyIsDown`, every cap knows when
    /// it is under a finger.
    @State private var liveFlags: NSEvent.ModifierFlags = []
    @State private var keyIsDown = false
    @State private var recording = false
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var rejected: String?
    @State private var recorder = HotkeyRecorder()
    @State private var monitor: Any?
    @State private var tapDetector = ModifierTapDetector()

    var body: some View {
        VStack(spacing: 14) {
            field
            status
        }
        .onAppear { if liveHighlight { watchKeys() } }
        .onDisappear { stopEverything() }
        .onChange(of: binding) { _, _ in
            // A new shortcut (a preset, say) re-arms the live watch so it can be
            // tried, and clears any stale error.
            rejected = nil
            held = false
            if liveHighlight, !recording { watchKeys() }
        }
    }

    /// Click it and it listens. Same shape either way, so the keys you press
    /// land where the old ones were.
    private var field: some View {
        Button { recording ? stopRecording() : startRecording() } label: {
            HStack(spacing: 8) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, part in
                    keyCap(part)
                }
                Spacer(minLength: 14)
                Text(recording ? "Esc to keep the old one" : "Click to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 430)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.primaryInk.opacity(recording ? 0.08 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(fieldEdge, lineWidth: recording || held ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        // No animation on the press. A key is down or it is not, and a fade in
        // between reads as lag.
        .animation(.easeOut(duration: 0.15), value: recording)
    }

    private var fieldEdge: Color {
        if recording || held { return theme.accent }
        return confirmed ? .green : theme.primaryInk.opacity(0.12)
    }

    /// What the field shows: the live keys while recording, the saved shortcut
    /// otherwise. A press still waiting for its key gets a placeholder cap.
    private var caps: [String] {
        guard recording else { return binding.parts }
        return HotkeyBinding.modifierParts(modifiers) + ["?"]
    }

    private func keyCap(_ part: String) -> some View {
        let down = isDown(part)
        return Text(part)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(part == "?" ? .secondary : (down ? theme.accent : .primary))
            .frame(minWidth: 52, minHeight: 52)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(down ? AnyShapeStyle(theme.accent.opacity(0.16)) : AnyShapeStyle(.background.secondary))
                    .shadow(color: .black.opacity(down ? 0.05 : 0.18), radius: 3, y: down ? 0 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        down ? theme.accent : (confirmed ? .green : Color.secondary.opacity(0.25)),
                        lineWidth: 1.5)
            )
            // Pressed keys sit a hair lower, the way a real one does.
            .offset(y: down ? 2 : 0)
    }

    /// One cap at a time: each lights under its own finger, the moment that key
    /// goes down. While recording every cap on screen is a key being held.
    private func isDown(_ part: String) -> Bool {
        if recording { return part != "?" }
        if binding.isModifierTap { return held }
        if part == binding.parts.last { return keyIsDown }
        return HotkeyBinding.modifierParts(liveFlags).contains(part)
    }

    @ViewBuilder
    private var status: some View {
        if let rejected {
            Label(rejected, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        } else if recording {
            Text(modifiers.isEmpty
                 ? "Press any keys. One modifier alone works."
                 : "Add a key, or let go to use \(HotkeyBinding.modifierParts(modifiers).joined()) alone.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)
        } else if showStatus {
            if confirmed {
                Label("That is it. It works.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if binding.needsAccessibility, !trusted {
                Label("Works here. Needs Accessibility for other apps.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Text(binding.isModifierTap ? "Tap it now to try it." : "Press it now to try it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording() {
        stopWatching()
        rejected = nil
        modifiers = []
        held = false
        recording = true
        recorder.start(held: { modifiers = $0 }, capture: captured)
    }

    /// Ends the listening state and leaves the shortcut as it was.
    private func stopRecording() {
        recorder.stop()
        recording = false
        modifiers = []
        if liveHighlight { watchKeys() }
    }

    private func captured(_ candidate: HotkeyBinding) {
        // Esc backs out, the same way it does everywhere else on the Mac.
        if candidate.isEscape {
            rejected = nil
            stopRecording()
            return
        }
        // Keep listening on a bad one, so a stray key is not a dead end.
        if let problem = candidate.problem {
            rejected = problem
            return
        }
        rejected = nil
        stopRecording()
        onCommit(candidate)
    }

    /// Watches our own window for the shortcut, so a press can be previewed and
    /// confirmed before macOS has been told to trust Drawer anywhere else.
    private func watchKeys() {
        stopWatching()
        tapDetector = ModifierTapDetector()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
            return (suppressMatchingPress && binding.matches(event)) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
            liveFlags = flags
            if binding.isModifierTap {
                trackTap(event, flags: flags)
            } else {
                // The modifiers of a combination, all down and nothing extra.
                held = !binding.eventFlags.isEmpty && flags == binding.eventFlags
            }
        case .keyDown:
            tapDetector.otherActivity()
            if binding.matches(event) {
                keyIsDown = true
                held = true
                onGoodPress?()
            }
        case .keyUp:
            if event.keyCode == UInt16(binding.keyCode) { keyIsDown = false }
            held = false
        default:
            break
        }
    }

    private func trackTap(_ event: NSEvent, flags: NSEvent.ModifierFlags) {
        guard let flag = binding.tapFlag, event.keyCode == UInt16(binding.keyCode) else {
            tapDetector.otherActivity()
            held = false
            return
        }
        if flags.contains(flag) {
            held = true
            tapDetector.down(at: event.timestamp)
        } else {
            held = false
            if tapDetector.up(at: event.timestamp) { onGoodPress?() }
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = false
        keyIsDown = false
        liveFlags = []
    }

    private func stopEverything() {
        stopWatching()
        recorder.stop()
    }
}
