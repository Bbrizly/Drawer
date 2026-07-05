import AppKit
import ApplicationServices
import CoreGraphics
import DrawerCore
import Foundation

/// Watches the frontmost app and window title and emits `ActivitySample`s plus
/// close boundaries (idle, sleep, lock). Event-driven: NSWorkspace for app
/// switches, an AXObserver for title/focus changes, and a 60s idle timer that
/// only runs while sampling. All AppKit/AX lives here so DrawerCore stays pure.
///
/// Runtime behavior needs real-device verification (Accessibility permission,
/// live AX events); the fold logic it feeds is unit-tested in DrawerCore.
@MainActor
final class ActivitySampler {
    var onSample: ((ActivitySample) -> Void)?
    var onBoundary: ((SessionBoundary) -> Void)?

    private let idleThreshold: TimeInterval = 180
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var idleTimer: Timer?
    private var isIdle = false
    private var running = false

    /// Prompts for Accessibility if needed. Returns whether the process is
    /// already trusted (sampling only proceeds when true).
    @discardableResult
    static func ensureAccessibilityTrust(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard !running, Self.ensureAccessibilityTrust(prompt: true) else { return }
        running = true

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        attachAX(to: NSWorkspace.shared.frontmostApplication)
        emitSample()

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    func stop() {
        guard running else { return }
        running = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        idleTimer?.invalidate()
        idleTimer = nil
        detachAX()
    }

    // MARK: events

    @objc private func appActivated() {
        attachAX(to: NSWorkspace.shared.frontmostApplication)
        checkIdle()
        emitSample()
    }

    @objc private func willSleep() {
        onBoundary?(SessionBoundary(ts: Date(), reason: .sleep))
    }

    @objc private func screenLocked() {
        onBoundary?(SessionBoundary(ts: Date(), reason: .lock))
    }

    /// A title change on the frontmost app. Called from the AX C callback.
    fileprivate func titleChanged() {
        checkIdle()
        emitSample()
    }

    private func emitSample() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        onSample?(ActivitySample(
            ts: Date(),
            bundleID: app.bundleIdentifier ?? "unknown",
            appName: app.localizedName ?? "unknown",
            windowTitle: focusedWindowTitle(of: app)))
    }

    /// System idle in seconds since the last input of any kind.
    private func systemIdleSeconds() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func checkIdle() {
        let idle = systemIdleSeconds()
        if idle >= idleThreshold, !isIdle {
            isIdle = true
            // Close the block at the moment input actually stopped.
            onBoundary?(SessionBoundary(ts: Date().addingTimeInterval(-idle), reason: .idle))
        } else if idle < idleThreshold {
            isIdle = false
        }
    }

    // MARK: Accessibility

    private func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &window) == .success,
            let windowElement = window
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowElement as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String  // per-window read can fail; caller keeps the app name
    }

    private func attachAX(to app: NSRunningApplication?) {
        guard let app, app.processIdentifier != observedPID else { return }
        detachAX()
        let pid = app.processIdentifier

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let sampler = Unmanaged<ActivitySampler>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in sampler.titleChanged() }
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let axApp = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, axApp, kAXTitleChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, axApp, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedPID = pid
    }

    private func detachAX() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObserver = nil
        observedPID = nil
    }

    deinit {
        // Tear down everything even if stop() wasn't called, so the AX callback's
        // unretained refcon can never fire against a freed sampler.
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        idleTimer?.invalidate()
        if let observer = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
