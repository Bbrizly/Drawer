import AppKit
import Carbon.HIToolbox

struct HotkeyBinding: Equatable, Hashable, Identifiable {
    let keyCode: UInt32
    let modifiers: UInt32

    var id: String { "\(keyCode)-\(modifiers)" }

    /// The combination in a key press, so a recorder can hand back what was
    /// actually typed.
    init(_ event: NSEvent) {
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: Self.carbonModifiers(event.modifierFlags)
        )
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

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

    /// Esc, pressed on its own. A recorder reads that as "leave it alone".
    var isEscape: Bool { isSingleKey && keyCode == UInt32(kVK_Escape) }

    /// Marks "the modifier key itself, tapped on its own". Carbon modifier
    /// masks live in the low bits, so this one is never part of a real set.
    static let tapMarker: UInt32 = 1 << 16

    /// One modifier key, tapped and released with nothing else touched. Carbon
    /// cannot register that, so it runs on the tap monitor instead.
    var isModifierTap: Bool { modifiers == Self.tapMarker }

    static func tap(_ keyCode: UInt32) -> HotkeyBinding {
        HotkeyBinding(keyCode: keyCode, modifiers: tapMarker)
    }

    /// The flag the tapped key carries, so a monitor can tell down from up.
    /// Nil when this is not a modifier key at all.
    var tapFlag: NSEvent.ModifierFlags? {
        switch keyCode {
        case UInt32(kVK_Command), UInt32(kVK_RightCommand): return .command
        case UInt32(kVK_Option), UInt32(kVK_RightOption): return .option
        case UInt32(kVK_Control), UInt32(kVK_RightControl): return .control
        case UInt32(kVK_Shift), UInt32(kVK_RightShift): return .shift
        case UInt32(kVK_Function): return .function
        default: return nil
        }
    }

    /// A tap is caught by watching every key press in every app, which macOS
    /// only allows once Drawer is trusted for Accessibility.
    var needsAccessibility: Bool { isModifierTap }

    /// Why this cannot be the shortcut, or nil when it can.
    var problem: String? {
        if isModifierTap {
            guard !appStoreBuild else {
                return "A single modifier needs Accessibility, which this version cannot ask for. "
                    + "Hold it with another key instead."
            }
            return tapFlag == nil ? "That is not a modifier key." : nil
        }
        // A bare typing key would fire in the middle of a sentence.
        return isTypingKey ? "That key types. Hold a modifier with it, or use F13 to F19." : nil
    }

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

    /// Single modifier keys worth offering: the ones nothing else on a Mac
    /// wants on their own.
    static let tapPresets: [HotkeyBinding] = [
        .tap(UInt32(kVK_RightCommand)), .tap(UInt32(kVK_RightOption)), .tap(UInt32(kVK_Function)),
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
        // A tapped modifier is the whole shortcut, so it draws as one cap.
        guard modifiers != tapMarker else { return [keyName(for: keyCode)] }
        return modifierParts(modifiers) + [keyName(for: keyCode)]
    }

    /// The modifier caps on their own, for a field drawing keys as they go down.
    static func modifierParts(_ flags: NSEvent.ModifierFlags) -> [String] {
        modifierParts(carbonModifiers(flags))
    }

    static func modifierParts(_ modifiers: UInt32) -> [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
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
        // The modifier keys themselves, named by side, for tap shortcuts.
        case UInt32(kVK_Command): return "⌘"
        case UInt32(kVK_RightCommand): return "right ⌘"
        case UInt32(kVK_Option): return "⌥"
        case UInt32(kVK_RightOption): return "right ⌥"
        case UInt32(kVK_Control): return "⌃"
        case UInt32(kVK_RightControl): return "right ⌃"
        case UInt32(kVK_Shift): return "⇧"
        case UInt32(kVK_RightShift): return "right ⇧"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter): return "Return"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Escape): return "Esc"
        case UInt32(kVK_Delete), UInt32(kVK_ForwardDelete): return "Delete"
        case UInt32(kVK_CapsLock): return "Caps Lock"
        case UInt32(kVK_Function): return "fn"
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
