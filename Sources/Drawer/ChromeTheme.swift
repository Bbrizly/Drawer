import AppKit
import SwiftUI

/// Settings and the first-run walkthrough are their own windows, so they never
/// inherit the drawer's theme the way the panel's own subviews do. This puts
/// them on the same surface: the theme's paper, its accent, its ink, and the
/// system appearance that matches, so AppKit-drawn controls (switches,
/// sliders, popup buttons) come out dark on paper and light on a dark board.
private struct ChromeThemeModifier: ViewModifier {
    @AppStorage("drawerTheme") private var themeRaw = DrawerTheme.default.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var theme: DrawerTheme { DrawerTheme(rawValue: themeRaw) ?? .default }

    func body(content: Content) -> some View {
        content
            .environment(\.drawerTheme, theme)
            .environment(\.colorScheme, theme.forcedColorScheme ?? systemScheme)
            .tint(theme.accent)
            // Forms and scroll views read this from the environment, so one
            // call here strips every grouped Form's own backing and lets the
            // paper below show through.
            .scrollContentBackground(.hidden)
            .background(theme.chromeSurface)
            .background(WindowAppearance(scheme: theme.forcedColorScheme))
            .animation(.easeInOut(duration: 0.25), value: theme)
    }
}

extension View {
    /// Dress a chrome window (Settings, the walkthrough) in the picked theme.
    func chromeThemed() -> some View { modifier(ChromeThemeModifier()) }
}

/// Pins the host window's appearance so AppKit controls resolve for the theme's
/// lightness, not the OS setting. nil follows the system, which is what the
/// glass and material themes want.
private struct WindowAppearance: NSViewRepresentable {
    let scheme: ColorScheme?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let name: NSAppearance.Name? = scheme.map { $0 == .dark ? .darkAqua : .aqua }
        let appearance = name.flatMap(NSAppearance.init(named:))
        // The window is not attached yet on the first layout pass.
        DispatchQueue.main.async { view.window?.appearance = appearance }
    }
}

/// A live preview tile for one theme: the real panel surface behind a couple of
/// stand-in ink bars, with the theme's accent and a selection ring. Settings
/// and the walkthrough both pick themes with this, so they look the same.
struct ThemeSwatch: View {
    let theme: DrawerTheme
    let selected: Bool
    var height: CGFloat = 62

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                PanelBackground(theme: theme)
                    .clipShape(shape)
                VStack(alignment: .leading, spacing: 5) {
                    Circle().fill(theme.accent).frame(width: 9, height: 9)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryInk.opacity(0.85))
                        .frame(width: 48, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.primaryInk.opacity(0.5))
                        .frame(width: 34, height: 5)
                }
                .padding(11)
            }
            .frame(height: height)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    // The ring wears the tile's own accent, so picking a theme
                    // shows that theme's color rather than the system blue.
                    selected ? theme.accent : Color.primary.opacity(0.12),
                    lineWidth: selected ? 2.5 : 1
                )
            )
            Text(theme.displayName)
                .font(.caption)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
