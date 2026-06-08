import SwiftUI

/// Visual skin for the drawer. The three themes share one layout and differ
/// only in these style tokens, so feature views read tokens and never branch
/// on the theme. The one exception is the panel plate (a view-builder
/// concern), which lives in `PanelBackground` below so the glass API sits in
/// exactly one place.
enum DrawerTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    case reminders
    case widget

    static let `default` = DrawerTheme.liquidGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .reminders: return "Reminders"
        case .widget: return "Widget"
        }
    }

    // MARK: Surface

    var panelCornerRadius: CGFloat {
        switch self {
        case .liquidGlass: return 20
        case .reminders: return 14
        case .widget: return 22
        }
    }

    // MARK: Rows

    /// SF Symbol point size for the task checkbox.
    var checkboxSize: CGFloat {
        switch self {
        case .liquidGlass: return 15
        case .reminders: return 18
        case .widget: return 14
        }
    }

    var rowVerticalPadding: CGFloat {
        switch self {
        case .reminders: return 8
        default: return 7
        }
    }

    /// Reminders separates rows with hairlines; the others rely on hover only.
    var showsRowSeparators: Bool { self == .reminders }

    // MARK: Type

    var fontDesign: Font.Design {
        switch self {
        case .widget: return .rounded
        default: return .default
        }
    }

    // MARK: Section headers

    var sectionHeaderUppercased: Bool { self != .reminders }

    /// Reminders colors its section titles with the accent, Apple-style.
    var sectionHeaderTinted: Bool { self == .reminders }

    var sectionHeaderFont: Font {
        switch self {
        case .liquidGlass, .widget: return .system(size: 10, weight: .bold)
        case .reminders: return .system(size: 13, weight: .bold)
        }
    }
}

// MARK: - Panel background

/// The drawer's backing plate. Isolated so the `.glassEffect` call exists in
/// one place and the rest of the UI stays glass-agnostic. The window draws the
/// drop shadow (NSPanel.hasShadow); this view owns the fill and edge per theme.
struct PanelBackground: View {
    let theme: DrawerTheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        switch theme {
        case .liquidGlass:
            // Real Liquid Glass. A faint scrim keeps text legible over bright
            // wallpapers, since glass samples whatever is behind the panel.
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(shape.fill(Color.black.opacity(0.05)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
        case .reminders:
            // Near-opaque: the calm, maximally-legible escape hatch.
            shape.fill(.regularMaterial)
                .overlay(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.55)))
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        case .widget:
            // Notification Center widget vibe: light material, gentle dim.
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.10)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        }
    }
}

// MARK: - Environment

private struct DrawerThemeKey: EnvironmentKey {
    static let defaultValue = DrawerTheme.default
}

extension EnvironmentValues {
    var drawerTheme: DrawerTheme {
        get { self[DrawerThemeKey.self] }
        set { self[DrawerThemeKey.self] = newValue }
    }
}
