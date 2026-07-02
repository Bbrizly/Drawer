import SwiftUI

struct DrawerIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let helpText: String
    var isProminent = false
    var isSelected = false
    var action: () -> Void

    @Environment(\.drawerTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 30, height: 30)
                .background(
                    backgroundStyle,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    if isProminent {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.onAccent.opacity(0.18), lineWidth: 0.5)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
        // Theme ink, not the system gray, so icons match the surface's world
        // (walnut on parchment, cool white in the arcade).
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
