import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

let rightCommandLog = Logger(subsystem: "com.bassam.drawer", category: "rightCommandTap")

/// Decides whether a right Command press counts as a "tap". A tap is a quick
/// press and release with nothing else touched in between, so a real
/// right-Command shortcut never triggers the drawer.
struct RightCommandTapDetector {
    /// The longest a tap may last. Hold longer and it is treated as a real
    /// modifier press, not a tap.
    var maxTapDuration: TimeInterval = 0.4

    private var pressedAt: TimeInterval?
    private var cancelled = false

    var isTracking: Bool { pressedAt != nil }

    mutating func commandDown(at time: TimeInterval) {
        pressedAt = time
        cancelled = false
    }

    /// Returns true when the release completes a clean tap.
    mutating func commandUp(at time: TimeInterval) -> Bool {
        defer {
            pressedAt = nil
            cancelled = false
        }
        guard let pressedAt, !cancelled else { return false }
        return time - pressedAt <= maxTapDuration
    }

    /// Any other key or modifier while the tap is in flight cancels it.
    mutating func otherActivity() {
        if pressedAt != nil { cancelled = true }
    }
}

/// Thin wrapper on macOS accessibility trust, the permission a global key
/// monitor needs.
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Opens the system prompt that sends the user to grant access.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Jumps straight to the Accessibility list in System Settings.
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Watches for a single tap of the right Command key, anywhere, and calls back.
/// Uses NSEvent monitors, which for keyboard events need accessibility trust.
@MainActor
final class RightCommandTapMonitor {
    private var monitors: [Any] = []
    private var detector = RightCommandTapDetector()
    private var onTap: (() -> Void)?

    private let rightCommandKeyCode = UInt16(kVK_RightCommand)

    var isRunning: Bool { !monitors.isEmpty }

    func start(onTap: @escaping () -> Void) {
        self.onTap = onTap
        guard !isRunning else { return }

        addMonitor(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        // Any real keypress during the hold means this was a shortcut, not a tap.
        addMonitor(matching: .keyDown) { [weak self] _ in
            self?.detector.otherActivity()
        }
        rightCommandLog.notice("tap monitor started, \(self.monitors.count) monitors installed")
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        detector = RightCommandTapDetector()
        onTap = nil
    }

    private func addMonitor(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) {
        // Global catches events aimed at other apps; local catches our own
        // windows. The two never fire for the same event, so no double count.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: {
            handler($0)
            return $0
        }) {
            monitors.append(local)
        }
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == rightCommandKeyCode else {
            detector.otherActivity()
            return
        }
        if event.modifierFlags.contains(.command) {
            detector.commandDown(at: event.timestamp)
        } else if detector.commandUp(at: event.timestamp) {
            rightCommandLog.notice("right command tap fired")
            onTap?()
        }
    }

    deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
