import AppKit
import SwiftUI

// MARK: - Bevel chrome

/// Classic Windows XP 3D border. Raised reads like a button; sunken reads like
/// a text field or list inset.
enum XPBevelStyle {
    case raised, sunken
}

struct XPBevelBorder: View {
    var style: XPBevelStyle = .raised
    var highlight: Color = .white
    var shadow: Color = Palette.xpBevelShadow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Canvas { ctx, _ in
                let hi = highlight
                let lo = shadow
                switch style {
                case .raised:
                    drawEdge(ctx, from: .zero, to: CGPoint(x: w, y: 0), color: hi)
                    drawEdge(ctx, from: .zero, to: CGPoint(x: 0, y: h), color: hi)
                    drawEdge(ctx, from: CGPoint(x: 0, y: h - 1), to: CGPoint(x: w, y: h - 1), color: lo)
                    drawEdge(ctx, from: CGPoint(x: w - 1, y: 0), to: CGPoint(x: w - 1, y: h), color: lo)
                case .sunken:
                    drawEdge(ctx, from: .zero, to: CGPoint(x: w, y: 0), color: lo)
                    drawEdge(ctx, from: .zero, to: CGPoint(x: 0, y: h), color: lo)
                    drawEdge(ctx, from: CGPoint(x: 0, y: h - 1), to: CGPoint(x: w, y: h - 1), color: hi)
                    drawEdge(ctx, from: CGPoint(x: w - 1, y: 0), to: CGPoint(x: w - 1, y: h), color: hi)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawEdge(_ ctx: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        ctx.stroke(path, with: .color(color), lineWidth: 1)
    }
}

/// A flat XP control surface with a sunken bevel and Luna gradient fill.
struct XPSunkenPanel: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Palette.xpControlTop, Palette.xpControlBottom],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(XPBevelBorder(style: .sunken))
    }
}

/// A raised XP toolbar / button plate.
struct XPRaisedPanel: View {
    var active = false

    var body: some View {
        Rectangle()
            .fill(buttonFill)
            .overlay(XPBevelBorder(style: active ? .sunken : .raised))
    }

    private var buttonFill: LinearGradient {
        if active {
            return LinearGradient(
                colors: [Palette.xpActiveBottom, Palette.xpActiveTop],
                startPoint: .top, endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [Palette.xpControlTop, Palette.xpControlBottom],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Title bar

/// A Luna window title bar: glossy blue band, an app icon and caption on the
/// left, and the three caption buttons on the right. The buttons drive real
/// actions (this is a panel, so minimize and close both dismiss it, maximize
/// toggles the panel height) so none of them are decorative.
struct XPTitleBar: View {
    var title: String = "Drawer"
    var onMinimize: () -> Void
    var onMaximize: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
            Text(title)
                .font(FontLoader.xpFont(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                XPCaptionButton(kind: .minimize, action: onMinimize)
                XPCaptionButton(kind: .maximize, action: onMaximize)
                XPCaptionButton(kind: .close, action: onClose)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(XPTitleBand())
    }
}

/// The glossy blue fill of the title bar: a base Luna gradient with a bright
/// gloss over the top half and a faint dark lip at the very bottom.
private struct XPTitleBand: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Palette.xpTitleTop, Palette.xpTitleBottom],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(LinearGradient(stops: [
                .init(color: .white.opacity(0.42), location: 0),
                .init(color: .white.opacity(0.06), location: 0.5),
                .init(color: .clear, location: 0.5),
                .init(color: .black.opacity(0.12), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                Color.white.opacity(0.5).frame(height: 1)
            }
            .allowsHitTesting(false)
    }
}

/// One caption button (minimize, maximize/restore, close). Close is the red
/// Luna button; the other two are glossy blue. All raised, brightening on hover.
struct XPCaptionButton: View {
    enum Kind { case minimize, maximize, close }
    let kind: Kind
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .brightness(hovering ? 0.08 : 0)
                Image(systemName: glyph)
                    .font(.system(size: kind == .close ? 9 : 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 0.5)
            }
            .frame(width: 21, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }

    private var glyph: String {
        switch kind {
        case .minimize: return "minus"
        case .maximize: return "square"
        case .close: return "xmark"
        }
    }

    private var label: String {
        switch kind {
        case .minimize: return "Minimize"
        case .maximize: return "Maximize"
        case .close: return "Close"
        }
    }

    private var fill: LinearGradient {
        if kind == .close {
            return LinearGradient(stops: [
                .init(color: .white.opacity(0.6), location: 0),
                .init(color: Palette.xpRedTop, location: 0.35),
                .init(color: Palette.xpRedBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(stops: [
            .init(color: .white.opacity(0.75), location: 0),
            .init(color: Palette.xpTitleTop, location: 0.5),
            .init(color: Palette.xpTitleBottom, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// The beige menu/toolbar band that sits under the title bar and over the white
/// client area, with a two-tone etched line along its bottom edge.
struct XPMenuBand: View {
    var body: some View {
        Palette.xpBeige
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Palette.xpBeigeShadow.frame(height: 1)
                    Color.white.opacity(0.8).frame(height: 1)
                }
            }
    }
}

// MARK: - Checkbox

/// 13×13 Luna checkbox: sunken white square, black tick when checked.
struct XPCheckbox: View {
    var done: Bool
    var inProgress: Bool
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .overlay(XPBevelBorder(style: .sunken))
            if done {
                XPCheckmark()
                    .stroke(Palette.xpInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .square, lineJoin: .miter))
                    .frame(width: size * 0.55, height: size * 0.42)
            } else if inProgress {
                Rectangle()
                    .fill(Palette.xpSelection)
                    .frame(width: max(2, size * 0.42), height: size - 4)
            }
        }
        .frame(width: 24, height: 24)
    }
}

private struct XPCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - Toolbar icon

struct XPToolbarIcon: View {
    let systemName: String
    var active = false
    var prominent = false
    var size: CGFloat = 32
    var iconSize: CGFloat = 15
    var isHovering = false
    /// Sitting on a dark surface (the blue board title bar) → white ink.
    var onDark = false

    var body: some View {
        ZStack {
            // Real XP toolbar buttons are flat, raising only on hover and
            // sinking when toggled on; primary actions are a raised blue button.
            if prominent {
                Rectangle()
                    .fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.55), location: 0),
                        .init(color: Palette.xpTitleTop, location: 0.45),
                        .init(color: Palette.xpTitleBottom, location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay(XPBevelBorder(
                        style: .raised, highlight: .white.opacity(0.85), shadow: Palette.xpTitleBottom))
            } else if active {
                Rectangle()
                    .fill(Palette.xpBeige)
                    .overlay(XPBevelBorder(style: .sunken))
            } else if isHovering {
                XPRaisedPanel(active: false)
            }
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(FontLoader.xpFont(size: iconSize, weight: .bold))
                .foregroundStyle(iconInk)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }

    private var iconInk: Color {
        if prominent { return .white }
        if onDark && !isHovering { return .white }
        return Palette.xpInk.opacity(isHovering || active ? 1 : 0.9)
    }
}

// MARK: - View helpers

extension DrawerTheme {
    var usesXPChrome: Bool { self == .windowsXP }

    /// Square corners everywhere in the XP skin.
    var chromeCornerRadius: CGFloat {
        usesXPChrome ? 0 : panelCornerRadius
    }

    /// A theme-following UI font: Tahoma in the XP skin, the system font (in the
    /// given design) everywhere else. The one place chrome text resolves so the
    /// XP theme reads as one consistent face.
    func uiFont(size: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        guard usesXPChrome else { return .system(size: CGFloat(size), weight: weight, design: design) }
        return FontLoader.xpFont(size: CGFloat(size), weight: weight)
    }

    /// Background for floating bars (add field, sound controls, timers).
    @ViewBuilder
    func chromePanelBackground<S: Shape>(_ shape: S) -> some View {
        if usesXPChrome {
            shape.fill(LinearGradient(
                colors: [Palette.xpControlTop, Palette.xpControlBottom],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(shape.stroke(Palette.xpBevelShadow, lineWidth: 1))
        } else {
            shape.fill(controlFill)
        }
    }
}

/// True when XP toolbar buttons sit on a dark blue bar and need white ink.
private struct XPOnDarkKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var xpOnDarkChrome: Bool {
        get { self[XPOnDarkKey.self] }
        set { self[XPOnDarkKey.self] = newValue }
    }
}

extension View {
    /// XP timer pills fill the row so they line up and match each other; other
    /// themes size to their content and sit inline. Apply BEFORE the pill's
    /// `.background` so the chrome fills the full width in XP.
    @ViewBuilder
    func xpTimerWidth(_ theme: DrawerTheme) -> some View {
        if theme.usesXPChrome {
            frame(maxWidth: .infinity, alignment: .leading)
        } else {
            fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    func xpListSelection(_ active: Bool, theme: DrawerTheme) -> some View {
        if theme.usesXPChrome && active {
            self
                .background(Palette.xpSelection)
                .foregroundStyle(Color.white)
        } else {
            self
        }
    }
}
