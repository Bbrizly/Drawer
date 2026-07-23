import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

let tapLog = Logger(subsystem: "com.bbrizly.drawer", category: "modifierTap")

/// Decides whether a modifier press counts as a "tap". A tap is a quick press
/// and release with nothing else touched in between, so holding that modifier
/// for a real shortcut never triggers the drawer.
struct ModifierTapDetector {
    /// The longest a tap may last. Hold longer and it is treated as a real
    /// modifier press, not a tap.
    var maxTapDuration: TimeInterval = 0.4

    private var pressedAt: TimeInterval?
    private var cancelled = false

    var isTracking: Bool { pressedAt != nil }

    mutating func down(at time: TimeInterval) {
        pressedAt = time
        cancelled = false
    }

    /// Returns true when the release completes a clean tap.
    mutating func up(at time: TimeInterval) -> Bool {
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
    // The App Store build never touches the AX API: the sandbox denies it and
    // every accessibility-dependent feature is unreachable there.
    static var isTrusted: Bool { !appStoreBuild && AXIsProcessTrusted() }

    /// Opens the system prompt that sends the user to grant access.
    static func prompt() {
        guard !appStoreBuild else { return }
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

/// Watches for a single tap of one modifier key, anywhere, and calls back.
/// Uses NSEvent monitors. The global half needs accessibility trust; the local
/// half works inside our own windows either way, which is what lets the
/// walkthrough confirm a tap before the permission is granted.
@MainActor
final class ModifierTapMonitor {
    private var monitors: [Any] = []
    private var detector = ModifierTapDetector()
    private var onTap: (() -> Void)?
    private var key = UInt16(kVK_RightCommand)
    private var flag: NSEvent.ModifierFlags = .command

    var isRunning: Bool { !monitors.isEmpty }

    func start(
        key: UInt16 = UInt16(kVK_RightCommand),
        flag: NSEvent.ModifierFlags = .command,
        onTap: @escaping () -> Void
    ) {
        // A different key needs its monitors built around the new one.
        if isRunning, key != self.key { stop() }
        self.key = key
        self.flag = flag
        self.onTap = onTap
        guard !isRunning else { return }

        addMonitor(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        // Any real keypress during the hold means this was a shortcut, not a tap.
        addMonitor(matching: .keyDown) { [weak self] _ in
            self?.detector.otherActivity()
        }
        tapLog.notice("tap monitor started, \(self.monitors.count) monitors installed")
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        detector = ModifierTapDetector()
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
        guard event.keyCode == key else {
            detector.otherActivity()
            return
        }
        if event.modifierFlags.contains(flag) {
            detector.down(at: event.timestamp)
        } else if detector.up(at: event.timestamp) {
            tapLog.notice("modifier tap fired")
            onTap?()
        }
    }

    deinit {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
}
