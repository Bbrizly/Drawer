import AppKit
import SwiftUI

/// Visual skin for the drawer. Every color in the app comes from `Palette`
/// (below); views never write a raw `Color(red:...)`. Non-color layout tokens
/// (corner radii, checkbox size, fonts) still live on the theme since they are
/// not colors. Two base palettes, light and dark, cover the plain themes; the
/// art-directed themes (medieval, pixel, artistic, notebook) start from a base
/// and override the few colors that make their world.
enum DrawerTheme: String, CaseIterable, Identifiable {
    case liquidGlass
    case reminders
    case widget
    case medieval
    case pixel
    case artistic
    case notebook

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
        case .notebook: return "Notebook"
        }
    }

    /// Art-directed themes paint their own opaque world (see PanelBackground).
    var isArtDirected: Bool {
        switch self {
        case .medieval, .pixel, .artistic, .notebook: return true
        default: return false
        }
    }

    /// Art themes paint a fixed-lightness surface (cream paper, dark arcade),
    /// so the whole subtree must resolve its semantic colors (.primary,
    /// .secondary, materials, dividers) for that lightness no matter what the OS
    /// appearance is. Without this, a light theme in Dark Mode draws white icons
    /// on light paper. System themes return nil and follow the OS.
    var forcedColorScheme: ColorScheme? {
        switch self {
        case .notebook, .medieval: return .light
        case .pixel, .artistic: return .dark
        default: return nil
        }
    }

    /// Popovers are separate AppKit surfaces, so they do not reliably inherit
    /// the drawer's color scheme. Pin them to the theme's intended chrome.
    var popoverColorScheme: ColorScheme {
        switch self {
        case .reminders, .medieval, .notebook: return .light
        default: return .dark
        }
    }

    // MARK: - The one source of color

    /// Every color the theme shows. Plain themes take a base and change only the
    /// accent; art themes override more. Nothing outside this file defines a color.
    var palette: Palette {
        switch self {
        case .liquidGlass:
            return .dark
        case .reminders:
            return .light
        case .widget:
            return .dark
        case .medieval:
            var p = Palette.light
            p.accent = Color(red: 0.62, green: 0.20, blue: 0.15)          // wax-seal red
            p.primary = Color(red: 0.24, green: 0.16, blue: 0.09)         // walnut ink
            p.secondary = Color(red: 0.24, green: 0.16, blue: 0.09).opacity(0.72)
            p.tertiary = Color(red: 0.24, green: 0.16, blue: 0.09).opacity(0.45)
            p.controlFill = AnyShapeStyle(Color(red: 0.40, green: 0.28, blue: 0.15).opacity(0.16))
            // Antique gold, deep enough to hold ~4.5:1 contrast on the parchment
            // (the brighter leaf tone lives on in the frame inlay below).
            p.sectionHeader = AnyShapeStyle(Color(red: 0.54, green: 0.39, blue: 0.10))
            return p
        case .pixel:
            var p = Palette.dark
            p.accent = Color(red: 0.22, green: 0.84, blue: 1.0)           // arcade cyan
            p.primary = Color(red: 0.90, green: 0.92, blue: 1.0)          // cool white
            p.secondary = Color(red: 0.90, green: 0.92, blue: 1.0).opacity(0.7)
            p.tertiary = Color(red: 0.90, green: 0.92, blue: 1.0).opacity(0.45)
            p.controlFill = AnyShapeStyle(Color.white.opacity(0.07))
            p.sectionHeader = AnyShapeStyle(Color(red: 1.0, green: 0.82, blue: 0.25)) // arcade yellow
            return p
        case .artistic:
            var p = Palette.dark
            p.accent = Color(red: 1.0, green: 0.32, blue: 0.62)           // hot pink
            p.primary = .white
            p.secondary = Color.white.opacity(0.75)
            p.tertiary = Color.white.opacity(0.5)
            p.controlFill = AnyShapeStyle(Color.white.opacity(0.16))
            p.sectionHeader = AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.45, blue: 0.42),
                    Color(red: 1.0, green: 0.32, blue: 0.62),
                    Color(red: 0.60, green: 0.45, blue: 1.0),
                ],
                startPoint: .leading, endPoint: .trailing
            ))
            return p
        case .notebook:
            var p = Palette.light
            p.accent = Palette.inkBlue
            p.primary = Color(red: 0.11, green: 0.13, blue: 0.20)         // pen ink
            p.secondary = Color(red: 0.11, green: 0.13, blue: 0.20).opacity(0.62)
            p.tertiary = Color(red: 0.11, green: 0.13, blue: 0.20).opacity(0.40)
            p.controlFill = AnyShapeStyle(Palette.marginRed.opacity(0.10))
            p.sectionHeader = AnyShapeStyle(Palette.marginRed)
            return p
        }
    }

    // MARK: - Color accessors (all read the palette)

    var accent: Color { palette.accent }
    var primaryInk: Color { palette.primary }
    var secondaryInk: Color { palette.secondary }
    var tertiaryInk: Color { palette.tertiary }
    var danger: Color { Palette.danger }
    var controlFill: AnyShapeStyle { palette.controlFill }
    var sectionHeaderStyle: AnyShapeStyle? { palette.sectionHeader }

    /// A named sticky-card color. The single home for these six; both the board
    /// and the settings swatches read here. nil = yellow.
    func cardColor(_ key: String?) -> Color { Palette.card(key).color }

    // MARK: Surface

    var panelCornerRadius: CGFloat {
        switch self {
        case .liquidGlass: return 20
        case .reminders: return 14
        case .widget: return 22
        case .medieval: return 12
        case .pixel: return 6      // near-square, hard-edged game window
        case .artistic: return 22
        case .notebook: return 8
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
        case .notebook: return 16
        }
    }

    var rowVerticalPadding: CGFloat {
        switch self {
        case .reminders, .medieval: return 8
        case .notebook: return 9   // give each ruled line room to breathe
        default: return 7
        }
    }

    /// Pixel rows are sharp boxes; everything else softens the corner. Notebook
    /// rows are flush so they read as lines on the page.
    var rowCornerRadius: CGFloat {
        switch self {
        case .pixel: return 2
        case .notebook: return 0
        default: return 10
        }
    }

    /// Reminders and Medieval separate rows with hairlines; Notebook rules every
    /// row (see TaskRowView); the others rely on hover alone.
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

    /// The task title font at the user's size (Settings > Text, default 13).
    /// Pixel keeps its bitmap face, one point under the system size so the
    /// default matches its original 12pt look. The rest take the ambient
    /// design from the root `fontDesign`.
    func titleFont(size: Double) -> Font {
        self == .pixel
            ? .custom(FontLoader.pixelFamily, size: CGFloat(size) - 1)
            : .system(size: CGFloat(size))
    }

    // MARK: Section headers

    var sectionHeaderUppercased: Bool { self != .reminders }

    /// Reminders colors its section titles with the accent, Apple-style.
    var sectionHeaderTinted: Bool { self == .reminders }

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

// MARK: - Palette

/// A color, stored as raw components so it works in both SwiftUI (`.color`) and
/// AppKit (`.ns`). Used for the fixed values (sticky cards, paper) that the
/// layer-backed board needs as NSColor. One definition, both worlds.
struct RGBA {
    let r, g, b, a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }
    var color: Color { Color(red: r, green: g, blue: b).opacity(a) }
    var ns: NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: a) }
}

/// The whole color world in one value. Chrome colors are SwiftUI `Color` (some
/// adaptive, like `.primary`); the fixed board/paper/card colors are `RGBA` so
/// the AppKit canvas can use them too. Themes build on `.light` / `.dark`.
struct Palette {
    var accent: Color
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var controlFill: AnyShapeStyle
    /// nil = default header styling (a bullet + primary/secondary).
    var sectionHeader: AnyShapeStyle?

    // Shared fixed values (same across themes; the board reads these as NSColor).
    static let inkBlue = Color(red: 0.13, green: 0.32, blue: 0.62)
    static let marginRed = Color(red: 0.75, green: 0.25, blue: 0.22)
    static let danger = Color(red: 0.90, green: 0.26, blue: 0.21)
    static let onAccent = Color.white   // text/hairline sitting on the accent fill
    /// X of the notebook red margin; the task list insets past it (DrawerView).
    static let notebookMargin: CGFloat = 40

    static let boardDark = RGBA(0.11, 0.11, 0.11)
    static let hitClear = RGBA(0, 0, 0, 0.01)           // invisible, keeps the window hit-testable
    static let cardInk = RGBA(0.12, 0.12, 0.12)         // text on a light card
    static let imageBackdrop = RGBA(0.25, 0.25, 0.25)   // behind a loading image
    static let paperFill = RGBA(0.99, 0.975, 0.93)      // warm cream
    static let paperLine = RGBA(0.55, 0.66, 0.86, 0.55) // faint blue rule

    /// The six sticky-card colors. The single source for the board and settings.
    static func card(_ key: String?) -> RGBA {
        switch key {
        case "pink": return RGBA(1.0, 0.80, 0.86)
        case "blue": return RGBA(0.74, 0.86, 1.0)
        case "green": return RGBA(0.79, 0.92, 0.74)
        case "purple": return RGBA(0.85, 0.81, 0.98)
        case "gray": return RGBA(0.86, 0.86, 0.86)
        default: return RGBA(0.99, 0.93, 0.62) // yellow
        }
    }
    static let cardKeys = ["yellow", "pink", "blue", "green", "purple", "gray"]

    // Color has only .primary and .secondary; tertiary is a fainter secondary.
    static let light = Palette(
        accent: .accentColor,
        primary: .primary,
        secondary: .secondary,
        tertiary: Color.secondary.opacity(0.6),
        controlFill: AnyShapeStyle(.quaternary.opacity(0.45)),
        sectionHeader: nil
    )

    static let dark = Palette(
        accent: .accentColor,
        primary: .primary,
        secondary: .secondary,
        tertiary: Color.secondary.opacity(0.6),
        controlFill: AnyShapeStyle(.quaternary.opacity(0.45)),
        sectionHeader: nil
    )
}

// MARK: - Panel background

/// The drawer's backing plate. Isolated so each surface (glass, material,
/// parchment, pixel frame, mesh, paper) lives in one place and the rest of the
/// UI stays surface-agnostic. The window draws the drop shadow; this owns the
/// fill and edge per theme.
struct PanelBackground: View {
    let theme: DrawerTheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.panelCornerRadius, style: .continuous)
    }

    @ViewBuilder
    var body: some View {
        switch theme {
        case .liquidGlass:
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(shape.fill(Color.black.opacity(0.05)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
        case .reminders:
            shape.fill(.regularMaterial)
                .overlay(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.55)))
                .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        case .widget:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.10)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        case .medieval:
            MedievalParchment(shape: shape)
        case .pixel:
            PixelFrame(shape: shape, accent: theme.accent)
        case .artistic:
            ArtisticMesh(shape: shape)
        case .notebook:
            NotebookPaper(shape: shape)
        }
    }
}

/// A sheet of classic loose-leaf: warm white stock, one crisp red margin rule,
/// and three punched binder holes down the left gutter. The horizontal rules are
/// drawn per task row (see TaskRowView) so tasks sit on them exactly; the task
/// list is inset past the margin (see DrawerView) so writing starts to its right.
private struct NotebookPaper: View {
    let shape: RoundedRectangle

    private let paper = Color(red: 0.985, green: 0.98, blue: 0.955) // warm white
    private let holeFill = Color(red: 0.90, green: 0.89, blue: 0.86)

    var body: some View {
        shape
            .fill(paper)
            // One clean red margin rule, just right of the punch holes.
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.marginRed.opacity(0.60))
                    .frame(width: 1.5)
                    .padding(.leading, Palette.notebookMargin)
            }
            // Three recessed holes: an inner shadow makes them read as cut out.
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let fractions: [CGFloat] = [0.18, 0.5, 0.82]
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(holeFill.shadow(.inner(color: .black.opacity(0.35), radius: 2, y: 1)))
                            .frame(width: 13, height: 13)
                            .position(x: 22, y: geo.size.height * fractions[i])
                    }
                }
            }
            .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
    }
}

/// Aged parchment: a warm gradient, faint foxing, a soft vignette, and a dark
/// frame double-ruled with a thin gold inlay.
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
            .overlay(
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

/// An 8-bit window: deep indigo fill, faint CRT scanlines, chunky double border.
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

/// Horizontal CRT scanlines, three pixels apart. Drawn once.
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

/// A vibrant nine-point mesh gradient with a soft dark vignette so white ink
/// stays readable. The signature "colourful artistic" surface.
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
        .overlay(
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
