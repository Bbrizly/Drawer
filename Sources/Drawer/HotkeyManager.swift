import Carbon.HIToolbox
import Foundation

struct HotkeyRegistration {
    private let unregisterHandler: () -> Void

    init(unregister: @escaping () -> Void) {
        self.unregisterHandler = unregister
    }

    func unregister() {
        unregisterHandler()
    }
}

final class HotkeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private var registration: HotkeyRegistration?
    private var activeKeyCode: UInt32?
    private var activeModifiers: UInt32?
    private let makeRegistration: (UInt32, UInt32) -> HotkeyRegistration?

    init(
        makeRegistration: ((UInt32, UInt32) -> HotkeyRegistration?)? = nil
    ) {
        self.makeRegistration = makeRegistration ?? { keyCode, modifiers in
            var hotKeyRef: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4452_5752), id: 1)
            let status = RegisterEventHotKey(
                keyCode,
                modifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            guard status == noErr, let hotKeyRef else { return nil }
            return HotkeyRegistration {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
    }

    @discardableResult
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping () -> Void
    ) -> Bool {
        self.handler = handler
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.handler?() }
                return noErr
            }, 1, &eventType, selfPtr, &eventHandlerRef)
        }
        return update(keyCode: keyCode, modifiers: modifiers)
    }

    /// Drops the shortcut entirely, for when the trigger moves to something
    /// Carbon cannot register (a tapped modifier).
    func unregister() {
        registration?.unregister()
        registration = nil
        activeKeyCode = nil
        activeModifiers = nil
    }

    /// Swaps the active key combination (settings change).
    @discardableResult
    func update(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let previousKeyCode = activeKeyCode
        let previousModifiers = activeModifiers
        registration?.unregister()
        registration = nil

        if let newRegistration = makeRegistration(keyCode, modifiers) {
            registration = newRegistration
            activeKeyCode = keyCode
            activeModifiers = modifiers
            return true
        }

        if let previousKeyCode, let previousModifiers,
           let restored = makeRegistration(previousKeyCode, previousModifiers) {
            registration = restored
            activeKeyCode = previousKeyCode
            activeModifiers = previousModifiers
        } else {
            activeKeyCode = nil
            activeModifiers = nil
        }
        return false
    }

    deinit {
        registration?.unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
