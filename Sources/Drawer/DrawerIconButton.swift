import SwiftUI

struct DrawerIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let helpText: String
    var isProminent = false
    var isSelected = false
    var size: CGFloat = 30
    var iconSize: CGFloat = 13
    var action: () -> Void

    @Environment(\.drawerTheme) private var theme
    @Environment(\.xpOnDarkChrome) private var xpOnDark
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            if theme.usesXPChrome {
                // Bigger hit target than the other themes; XP toolbar buttons
                // that are too tight feel fiddly to press.
                XPToolbarIcon(
                    systemName: systemName,
                    active: isSelected,
                    prominent: isProminent,
                    size: max(size + 4, 32),
                    iconSize: iconSize + 1,
                    isHovering: isHovering,
                    onDark: xpOnDark
                )
            } else {
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(foregroundStyle)
                    .frame(width: size, height: size)
                    .background(
                        backgroundStyle,
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    )
                    .overlay {
                        if isProminent {
                            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                                .stroke(Palette.onAccent.opacity(0.18), lineWidth: 0.5)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(helpText)
        .help(helpText)
        .onHover { hovering in
            // Fade the hover fill in and out. A hard swap reads as a flicker
            // when the pointer crosses the row of icons.
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(Palette.onAccent)
        }
        if isSelected {
            return AnyShapeStyle(theme.accent)
        }
        return AnyShapeStyle(theme.secondaryInk)
    }

    private var backgroundStyle: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(theme.accent.gradient)
        }
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.14))
        }
        return AnyShapeStyle(isHovering ? theme.primaryInk.opacity(0.09) : Color.clear)
    }
}

/// A small dip on press so plain buttons feel like they take the click. Used by
/// every custom button in the app, so they all press the same way.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}
