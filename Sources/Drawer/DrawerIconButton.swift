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
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
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
            return AnyShapeStyle(Color.white)
        }
        if isSelected {
            return AnyShapeStyle(theme.accent)
        }
        return AnyShapeStyle(Color.secondary)
    }

    private var backgroundStyle: AnyShapeStyle {
        if isProminent {
            return AnyShapeStyle(theme.accent.gradient)
        }
        if isSelected {
            return AnyShapeStyle(theme.accent.opacity(0.14))
        }
        return AnyShapeStyle(isHovering ? Color.secondary.opacity(0.12) : Color.clear)
    }
}
