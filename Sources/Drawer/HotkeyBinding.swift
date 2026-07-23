import AppKit
import Carbon.HIToolbox

struct HotkeyBinding: Equatable, Hashable, Identifiable {
    let keyCode: UInt32
    let modifiers: UInt32

    var id: String { "\(keyCode)-\(modifiers)" }

    var label: String { Self.label(keyCode: keyCode, modifiers: modifiers) }

    /// The label split up, so onboarding can draw one key cap per part.
    var parts: [String] { Self.parts(keyCode: keyCode, modifiers: modifiers) }

    /// The AppKit flags this binding's Carbon modifiers stand for, so a plain
    /// NSEvent can be checked against it.
    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// True when this key press is the shortcut. Caps Lock is ignored: it is
    /// never part of a binding and leaving it on should not block the press.
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(keyCode) else { return false }
        let pressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        return pressed == eventFlags
    }

    var isSingleKey: Bool { modifiers == 0 }

    /// Keys that are safe to bind globally with no modifiers.
    var isTypingKey: Bool {
        guard isSingleKey else { return false }
        return !Self.safeSingleKeys.contains(keyCode)
    }

    static let ctrlOptSpace = HotkeyBinding(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)
    )
    static let optSpace = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    static let ctrlOptD = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey)
    )
    static let cmdShiftSpace = HotkeyBinding(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)
    )

    static let singleKeyPresets: [HotkeyBinding] = [
        HotkeyBinding(keyCode: UInt32(kVK_F13), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F14), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F15), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F16), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F17), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F18), modifiers: 0),
        HotkeyBinding(keyCode: UInt32(kVK_F19), modifiers: 0),
    ]

    static let modifierPresets: [HotkeyBinding] = [
        .ctrlOptSpace, .optSpace, .ctrlOptD, .cmdShiftSpace,
    ]

    private static let safeSingleKeys: Set<UInt32> = Set(singleKeyPresets.map(\.keyCode) + [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
        UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
        UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F20),
        UInt32(kVK_Escape), UInt32(kVK_CapsLock), UInt32(kVK_Function),
    ])

    static var saved: HotkeyBinding {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hotkeyKeyCode") != nil {
            return HotkeyBinding(
                keyCode: UInt32(defaults.integer(forKey: "hotkeyKeyCode")),
                modifiers: UInt32(defaults.integer(forKey: "hotkeyModifiers"))
            )
        }
        return legacyPreset(defaults.string(forKey: "hotkeyPreset") ?? "") ?? .ctrlOptSpace
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: "hotkeyKeyCode")
        defaults.set(Int(modifiers), forKey: "hotkeyModifiers")
    }

    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        parts(keyCode: keyCode, modifiers: modifiers).joined()
    }

    static func parts(keyCode: UInt32, modifiers: UInt32) -> [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts
    }

    private static func legacyPreset(_ raw: String) -> HotkeyBinding? {
        switch raw {
        case "ctrlOptSpace": return .ctrlOptSpace
        case "optSpace": return .optSpace
        case "ctrlOptD": return .ctrlOptD
        case "cmdShiftSpace": return .cmdShiftSpace
        default: return nil
        }
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Escape): return "Esc"
        case UInt32(kVK_Delete), UInt32(kVK_ForwardDelete): return "Delete"
        case UInt32(kVK_CapsLock): return "Caps Lock"
        case UInt32(kVK_Function): return "Fn"
        case UInt32(kVK_F1): return "F1"
        case UInt32(kVK_F2): return "F2"
        case UInt32(kVK_F3): return "F3"
        case UInt32(kVK_F4): return "F4"
        case UInt32(kVK_F5): return "F5"
        case UInt32(kVK_F6): return "F6"
        case UInt32(kVK_F7): return "F7"
        case UInt32(kVK_F8): return "F8"
        case UInt32(kVK_F9): return "F9"
        case UInt32(kVK_F10): return "F10"
        case UInt32(kVK_F11): return "F11"
        case UInt32(kVK_F12): return "F12"
        case UInt32(kVK_F13): return "F13"
        case UInt32(kVK_F14): return "F14"
        case UInt32(kVK_F15): return "F15"
        case UInt32(kVK_F16): return "F16"
        case UInt32(kVK_F17): return "F17"
        case UInt32(kVK_F18): return "F18"
        case UInt32(kVK_F19): return "F19"
        case UInt32(kVK_F20): return "F20"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_UpArrow): return "↑"
        case UInt32(kVK_DownArrow): return "↓"
        default:
            if let chars = character(for: keyCode) { return chars }
            return "Key \(keyCode)"
        }
    }

    private static func character(for keyCode: UInt32) -> String? {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ) else { return nil }
        let chars = event.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? nil : chars.uppercased()
    }
}
