import Carbon.HIToolbox

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case ctrlOptSpace
    case optSpace
    case ctrlOptD
    case cmdShiftSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ctrlOptSpace: return "⌃⌥Space"
        case .optSpace: return "⌥Space"
        case .ctrlOptD: return "⌃⌥D"
        case .cmdShiftSpace: return "⌘⇧Space"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .ctrlOptSpace, .optSpace, .cmdShiftSpace: return UInt32(kVK_Space)
        case .ctrlOptD: return UInt32(kVK_ANSI_D)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .ctrlOptSpace: return UInt32(controlKey | optionKey)
        case .optSpace: return UInt32(optionKey)
        case .ctrlOptD: return UInt32(controlKey | optionKey)
        case .cmdShiftSpace: return UInt32(cmdKey | shiftKey)
        }
    }

    static var saved: HotkeyPreset {
        HotkeyPreset(
            rawValue: UserDefaults.standard.string(forKey: "hotkeyPreset") ?? ""
        ) ?? .ctrlOptSpace
    }
}
