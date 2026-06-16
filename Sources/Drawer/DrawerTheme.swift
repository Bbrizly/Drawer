import SwiftUI

/// Visual skin for the drawer. Themes share one layout and differ only in
/// these style tokens, so feature views read tokens and never branch on the
/// theme. The one exception is the panel plate (a view-builder concern), which
/// lives in `PanelBackground` below so each surface treatment sits in one place.
///
/// The first three are calm system-material skins (they ride the system accent
/// and label colors, so they adapt to light and dark). The last three are
/// fully art-directed worlds: parchment, 8-bit, and a vibrant mesh. Those carry
/// their own ink and accent so the whole mood holds together.
enum DrawerTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    case reminders
    case widget
    case medieval
    case pixel
    case artistic

    static let `default` = DrawerTheme.liquidGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .reminders: return "Reminders"
        case .widget: return "Widget"
        case .medieval: return "Medieval"
        case .pixel: return "Pixel"
        case .artistic: return "Artistic"
        }
    }

    /// Art-directed themes paint their own opaque world, so they own their ink
    /// and accent instead of borrowing the system's.
    var isArtDirected: Bool {
        switch self {
        case .medieval, .pixel, .artistic: return true
        default: return false
        }
    }

    // MARK: Palette

    /// Drives `.tint` and `Color.accentColor` substitutes across the UI.
    var accent: Color {
        switch self {
        case .medieval: return Color(red: 0.62, green: 0.20, blue: 0.15) // wax-seal red
        case .pixel: return Color(red: 0.22, green: 0.84, blue: 1.0)     // arcade cyan
        case .artistic: return Color(red: 1.0, green: 0.32, blue: 0.62)  // hot pink
        default: return .accentColor
        }
    }

    /// The base text color. Set once at the root so `.secondary` / `.tertiary`
    /// derive from it; art-directed themes use a hand-picked ink, the rest keep
    /// the adaptive system label color.
    var primaryInk: Color {
        switch self {
        case .medieval: return Color(red: 0.24, green: 0.16, blue: 0.09) // walnut
        case .pixel: return Color(red: 0.90, green: 0.92, blue: 1.0)     // cool white
        case .artistic: return .white
        default: return .primary
        }
    }

    /// Background for the small control chrome (the icon button cluster).
    var controlFill: AnyShapeStyle {
        switch self {
        case .medieval: return AnyShapeStyle(Color(red: 0.40, green: 0.28, blue: 0.15).opacity(0.16))
        case .pixel: return AnyShapeStyle(Color.white.opacity(0.07))
        case .artistic: return AnyShapeStyle(Color.white.opacity(0.16))
        default: return AnyShapeStyle(.quaternary.opacity(0.45))
        }
    }

    // MARK: Surface

    var panelCornerRadius: CGFloat {
        switch self {
        case .liquidGlass: return 20
        case .reminders: return 14
        case .widget: return 22
        case .medieval: return 12
        case .pixel: return 6      // near-square, hard-edged game window
        case .artistic: return 22
        }
    }

    // MARK: Rows

    /// SF Symbol point size for the task checkbox.
    var checkboxSize: CGFloat {
        switch self {
        case .liquidGlass: return 15
        case .reminders: return 18
        case .widget: return 14
        case .medieval: return 16
        case .pixel: return 15
        case .artistic: return 16
        }
    }

    var rowVerticalPadding: CGFloat {
        switch self {
        case .reminders, .medieval: return 8
        default: return 7
        }
    }

    /// Pixel rows are sharp boxes; everything else softens the corner.
    var rowCornerRadius: CGFloat { self == .pixel ? 2 : 10 }

    /// Reminders and Medieval separate rows with hairlines; the others rely on
    /// hover alone.
    var showsRowSeparators: Bool { self == .reminders || self == .medieval }

    /// Checkbox glyphs. Pixel swaps the round set for squares so it reads 8-bit.
    func checkboxSymbol(done: Bool, inProgress: Bool) -> String {
        if self == .pixel {
            if done { return "checkmark.square.fill" }
            if inProgress { return "square.lefthalf.filled" }
            return "square"
        }
        if done { return "checkmark.circle.fill" }
        if inProgress { return "circle.lefthalf.filled" }
        return "circle"
    }

    // MARK: Type

    var fontDesign: Font.Design {
        switch self {
        case .widget, .artistic: return .rounded
        case .medieval: return .serif
        case .pixel: return .monospaced
        default: return .default
        }
    }

    /// The task title font. Pixel uses its bitmap face; the rest take the
    /// ambient design from `fontDesign` via a plain text style.
    var titleFont: Font {
        self == .pixel ? .custom(FontLoader.pixelFamily, size: 12) : .callout
    }

    // MARK: Section headers

    var sectionHeaderUppercased: Bool { self != .reminders }

    /// Reminders colors its section titles with the accent, Apple-style.
    var sectionHeaderTinted: Bool { self == .reminders }

    /// Art-directed override for the section title fill. Medieval gilds it,
    /// Pixel uses arcade yellow, Artistic paints a gradient.
    var sectionHeaderStyle: AnyShapeStyle? {
        switch self {
        case .medieval: return AnyShapeStyle(Color(red: 0.70, green: 0.52, blue: 0.16)) // gold leaf
        case .pixel: return AnyShapeStyle(Color(red: 1.0, green: 0.82, blue: 0.25))      // arcade yellow
        case .artistic:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.45, blue: 0.42),
                    Color(red: 1.0, green: 0.32, blue: 0.62),
                    Color(red: 0.60, green: 0.45, blue: 1.0),
                ],
                startPoint: .leading, endPoint: .trailing
            ))
        default: return nil
        }
    }

    var sectionHeaderFont: Font {
        switch self {
        case .reminders: return .system(size: 13, weight: .bold)
        case .medieval: return .system(size: 11, weight: .bold) // serif via root design
        case .pixel: return .custom(FontLoader.pixelFamily, size: 11)
        case .artistic: return .system(size: 11, weight: .heavy)
        default: return .system(size: 10, weight: .bold)
        }
    }
}

// MARK: - Panel background

/// The drawer's backing plate. Isolated so each surface (glass, material,
/// parchment, pixel frame, mesh) lives in one place and the rest of the UI
/// stays surface-agnostic. The window draws the drop shadow (NSPanel.hasShadow);
/// this view owns the fill and edge per theme.
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
        case .medieval:
            MedievalParchment(shape: shape)
        case .pixel:
            PixelFrame(shape: shape, accent: theme.accent)
        case .artistic:
            ArtisticMesh(shape: shape)
        }
    }
}

/// Aged parchment: a warm gradient, a faint speckle of foxing, a soft vignette
/// at the edges, and a dark frame double-ruled with a thin gold inlay.
private struct MedievalParchment: View {
    let shape: RoundedRectangle

    var body: some View {
        shape
            .fill(LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.89, blue: 0.74),
                    Color(red: 0.89, green: 0.81, blue: 0.63),
                ],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(ParchmentGrain().opacity(0.05).clipShape(shape))
            .overlay( // vignette: darken toward the edges like old paper
                shape.fill(RadialGradient(
                    colors: [.clear, Color(red: 0.35, green: 0.24, blue: 0.10).opacity(0.22)],
                    center: .center, startRadius: 70, endRadius: 230
                ))
            )
            .overlay(shape.strokeBorder(Color(red: 0.31, green: 0.20, blue: 0.09), lineWidth: 1.5))
            .overlay(
                RoundedRectangle(cornerRadius: max(0, shape.cornerSize.width - 3), style: .continuous)
                    .strokeBorder(Color(red: 0.70, green: 0.52, blue: 0.16).opacity(0.55), lineWidth: 1)
                    .padding(3)
            )
    }
}

/// Deterministic foxing specks so the parchment is not a flat fill. Drawn once.
private struct ParchmentGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 10_000) / 10_000
            }
            for _ in 0..<420 {
                let x = next() * size.width
                let y = next() * size.height
                let r = 0.4 + next() * 1.1
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Color(red: 0.35, green: 0.22, blue: 0.08))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// An 8-bit window: deep indigo fill, faint CRT scanlines, and a chunky double
/// border (bright accent outside, dark inset) for that beveled game-UI look.
private struct PixelFrame: View {
    let shape: RoundedRectangle
    let accent: Color

    var body: some View {
        shape
            .fill(Color(red: 0.07, green: 0.07, blue: 0.20))
            .overlay(Scanlines().opacity(0.06).clipShape(shape))
            .overlay(shape.strokeBorder(accent.opacity(0.85), lineWidth: 2))
            .overlay(
                RoundedRectangle(cornerRadius: max(0, shape.cornerSize.width - 3), style: .continuous)
                    .strokeBorder(Color(red: 0.30, green: 0.32, blue: 0.70).opacity(0.7), lineWidth: 1)
                    .padding(3)
            )
    }
}

/// Horizontal CRT scanlines, two pixels apart. Drawn once.
private struct Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            var y = 0.0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black)
                )
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// A vibrant nine-point mesh gradient, jewel-toned, with a soft dark vignette so
/// white ink stays readable. The signature "colourful artistic" surface.
private struct ArtisticMesh: View {
    let shape: RoundedRectangle

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
                SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1.0, 0.5),
                SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0),
            ],
            colors: [
                Color(red: 0.42, green: 0.18, blue: 0.78), Color(red: 0.95, green: 0.27, blue: 0.55), Color(red: 1.0, green: 0.52, blue: 0.30),
                Color(red: 0.20, green: 0.42, blue: 0.92), Color(red: 0.65, green: 0.30, blue: 0.86), Color(red: 0.98, green: 0.35, blue: 0.62),
                Color(red: 0.12, green: 0.62, blue: 0.80), Color(red: 0.36, green: 0.34, blue: 0.88), Color(red: 0.80, green: 0.24, blue: 0.70),
            ]
        )
        .clipShape(shape)
        .overlay( // keep the corners readable under bright text
            shape.fill(RadialGradient(
                colors: [.clear, Color.black.opacity(0.28)],
                center: .center, startRadius: 80, endRadius: 240
            ))
        )
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
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
