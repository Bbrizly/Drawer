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
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(helpText)
        .help(helpText)
        .onHover { isHovering = $0 }
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
