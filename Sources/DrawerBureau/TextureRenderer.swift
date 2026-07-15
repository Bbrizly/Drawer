import AppKit
import SpriteKit

/// The Bureau scene keeps a Papers-Please look no matter which app theme is
/// active (spec Decision 5, risk 10), so it owns its own muted palette rather
/// than reading `DrawerTheme` (which lives in the `Drawer` target anyway).
/// Gritty paper, one red accent, dark ink.
///
/// Every value here loads from the `art` block of bureau-tuning.json via
/// `apply(_:)`, so an artist edits hex strings in the json (hot-reloaded) and
/// the whole Bureau recolors. The statics keep every call site a plain
/// `BureauPalette.cream` read. See Docs/BUREAU.md for the full editing guide.
enum BureauPalette {
    static private(set) var cream = color("#E3D6B8")
    static private(set) var creamShade = color("#CCBD9C")
    static private(set) var ink = color("#292621")
    static private(set) var inkFaint = color("#2926218C")
    static private(set) var red = color("#9E3326")
    /// The DONE stamp die and its ink (spec "The stamp"): a muted approval
    /// green sitting beside `red`'s POSTPONED in the same dusty register.
    static private(set) var stampGreen = color("#3D6B38")
    static private(set) var drawerFloor = color("#3D3624")
    static private(set) var drawerLip = color("#292417")
    static private(set) var tray = color("#5E523D")
    static private(set) var trayInk = color("#DED4BA")

    /// The Papers-Please stamp bar: near-black metal, a lighter edge, and the
    /// rivet dots at its corners.
    static private(set) var metal = color("#262626")
    static private(set) var metalEdge = color("#525252")
    static private(set) var rivet = color("#6B6B6B")

    /// The Bureau text face, from `art.fontFamily`. Defaults to the bundled
    /// pixel font the Pixel theme ships (registered process-wide at launch via
    /// `FontLoader.registerBundledFonts`). DrawerBureau cannot import `Drawer`,
    /// so the family is named directly; a missing registration (e.g. a bare
    /// unit test) falls back to a system face so the slip still renders
    /// legible ink.
    static private(set) var pixelFamily = "Pixelify Sans"

    static func titleFont(_ size: CGFloat) -> NSFont {
        NSFont(name: pixelFamily, size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }

    static func detailFont(_ size: CGFloat) -> NSFont {
        NSFont(name: pixelFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Loads the palette from the tuning's art block. A hex string that fails
    /// to parse leaves that color at its default rather than failing the load.
    static func apply(_ art: BureauArtTuning) {
        cream = color(art.paper)
        creamShade = color(art.paperShade)
        ink = color(art.ink)
        inkFaint = color(art.inkFaint)
        red = color(art.accent)
        stampGreen = color(art.approve)
        drawerFloor = color(art.drawerFloor)
        drawerLip = color(art.drawerLip)
        tray = color(art.tray)
        trayInk = color(art.trayInk)
        metal = color(art.metal)
        metalEdge = color(art.metalEdge)
        rivet = color(art.rivet)
        pixelFamily = art.fontFamily
    }

    /// "#RRGGBB" or "#RRGGBBAA" (leading # optional) to NSColor. Magenta on a
    /// bad string so a typo is visible in the scene instead of silently black.
    static func color(_ hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            return .magenta
        }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

/// Renders a task title to a cream receipt slip `NSImage` at the screen's
/// backing scale, nearest-neighbor, with baked jagged tears top and bottom, a
/// BIG readable title, and dot-matrix flavor in the details (spec "The drawer
/// scene"). Cached by (text, details, size, scale); re-rendered only when the
/// text or geometry changes, matching the spike-board `contentsScale`
/// discipline so the slip stays crisp instead of blurring at non-integer scale.
final class TextureRenderer {
    private struct Key: Hashable {
        let title: String
        let details: String
        let w: Int
        let h: Int
        let scale: Int
        let ageBucket: Int
        let showStubLine: Bool
    }

    private var cache: [Key: NSImage] = [:]

    /// The live art block: font sizes and pixel chunkiness. The palette part
    /// is applied globally via `BureauPalette.apply`; this copy drives the
    /// values baked into each slip render. Setting a changed art drops the
    /// cache, so every slip re-renders in the new style on its next read.
    var art = BureauArtTuning() {
        didSet { if art != oldValue { cache.removeAll() } }
    }

    /// The slip image at `size` points, backed by a `size * scale` pixel
    /// buffer. `age` is 0 (fresh off the printer) to 1 (weeks in the drawer);
    /// older paper yellows and foxes (R5 aging). Bucketed in the cache key so
    /// a slip re-renders a handful of times over its life, not per read.
    func image(title: String, details: String = "", size: CGSize, scale: CGFloat, age: Double = 0, showStubLine: Bool = true) -> NSImage {
        let bucket = Int((min(1, max(0, age)) * 4).rounded())
        let key = Key(
            title: title, details: details,
            w: Int(size.width.rounded()), h: Int(size.height.rounded()),
            scale: Int((scale * 100).rounded()),
            ageBucket: bucket, showStubLine: showStubLine
        )
        if let hit = cache[key] { return hit }
        let img = render(title: title, details: details, size: size, scale: scale, age: Double(bucket) / 4, showStubLine: showStubLine)
        cache[key] = img
        return img
    }

    /// A nearest-filtered `SKTexture` for a `ReceiptSprite`. The chunky pixel
    /// read comes from `.nearest` filtering when the physics world scales the
    /// sprite, so the slip never smears.
    func texture(title: String, details: String = "", size: CGSize, scale: CGFloat, age: Double = 0, showStubLine: Bool = true) -> SKTexture {
        let texture = SKTexture(image: image(title: title, details: details, size: size, scale: scale, age: age, showStubLine: showStubLine))
        texture.filteringMode = .nearest
        return texture
    }

    /// Drops the cache when the backing scale changes (a window moves to a
    /// different-density display), so the next render repopulates at the new
    /// scale. Called from `viewDidChangeBackingProperties` upstream.
    func invalidate() { cache.removeAll() }

    private func render(title: String, details: String, size: CGSize, scale: CGFloat, age: Double = 0, showStubLine: Bool = true) -> NSImage {
        // The pixelation knob: art.pixelScale divides the pixel density, and
        // the nearest-neighbor filtering in `texture` scales the small buffer
        // back up into chunky Papers-Please pixels. 1 renders crisp.
        let renderScale = max(0.25, scale / CGFloat(max(1, art.pixelScale)))
        let pxW = max(1, Int((size.width * renderScale).rounded()))
        let pxH = max(1, Int((size.height * renderScale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        // rep.size in points against a larger pixel buffer is the standard
        // Retina bitmap pattern: drawing in point space fills the pixel buffer
        // at `scale`, so a 96x144 slip at scale 2 is a 192x288 px image.
        rep.size = size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: size)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(title: title, details: details, in: size, age: age, showStubLine: showStubLine)
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    private func draw(title: String, details: String, in size: CGSize, age: Double = 0, showStubLine: Bool = true) {
        // Deterministic tears so the same task always looks the same slip.
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(title.hashValue)))
        let slip = slipPath(in: size, rng: &rng)

        BureauPalette.cream.setFill()
        slip.fill()

        // Aging (R5): older paper yellows toward the shade tone and picks up
        // foxing specks, so a slip that sat in the drawer for weeks looks it.
        if age > 0 {
            BureauPalette.creamShade.withAlphaComponent(0.45 * age).setFill()
            slip.fill()
            BureauPalette.ink.withAlphaComponent(0.10).setFill()
            for _ in 0..<Int(age * 26) {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let r = 0.5 + rng.next() * 1.2
                NSBezierPath(ovalIn: CGRect(x: x, y: y, width: r, height: r)).fill()
            }
        }

        // A soft bottom band shade so the paper reads as a physical object,
        // not a flat rectangle. Clipped inside a save/restore so it never
        // leaks the clip onto the text below.
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.28)).setClip()
        BureauPalette.creamShade.withAlphaComponent(0.5).setFill()
        slip.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let inset: CGFloat = 10
        let contentWidth = size.width - inset * 2

        // BIG readable title (legibility beats flavor at drawer scale). The
        // default 15pt reads big but still wraps cleanly on the narrow 96pt
        // portrait slip; art.titleFontSize tunes it.
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byWordWrapping
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: BureauPalette.titleFont(CGFloat(art.titleFontSize)),
            .foregroundColor: BureauPalette.ink,
            .paragraphStyle: titleStyle,
        ]
        let titleRect = CGRect(x: inset, y: size.height * 0.36, width: contentWidth, height: size.height * 0.58)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        // One red accent rule under the title.
        BureauPalette.red.setStroke()
        let rule = NSBezierPath()
        rule.lineWidth = 1.5
        rule.move(to: CGPoint(x: inset, y: size.height * 0.30))
        rule.line(to: CGPoint(x: size.width - inset, y: size.height * 0.30))
        rule.stroke()

        // Dot-matrix flavor line: a faint monospaced detail row at the foot.
        // Off for the cleaner Papers-Please filed-paper look.
        if showStubLine {
            let detail = details.isEmpty ? defaultDetail(&rng) : details
            let detailAttrs: [NSAttributedString.Key: Any] = [
                .font: BureauPalette.detailFont(CGFloat(art.detailFontSize)),
                .foregroundColor: BureauPalette.inkFaint,
            ]
            (detail as NSString).draw(
                at: CGPoint(x: inset, y: size.height * 0.10),
                withAttributes: detailAttrs
            )
        }
    }

    /// A cream slip rectangle with jagged torn edges along the top and bottom.
    private func slipPath(in size: CGSize, rng: inout SeededRNG) -> NSBezierPath {
        let path = NSBezierPath()
        let teeth = 14
        let dx = size.width / CGFloat(teeth)
        let topBase = size.height - 3
        let botBase: CGFloat = 3

        path.move(to: CGPoint(x: 0, y: botBase))
        for i in 0...teeth {
            let x = CGFloat(i) * dx
            let y = topBase - rng.next() * 4
            path.line(to: CGPoint(x: x, y: y))
        }
        path.line(to: CGPoint(x: size.width, y: botBase))
        for i in stride(from: teeth, through: 0, by: -1) {
            let x = CGFloat(i) * dx
            let y = botBase + rng.next() * 4
            path.line(to: CGPoint(x: x, y: y))
        }
        path.close()
        return path
    }

    private func defaultDetail(_ rng: inout SeededRNG) -> String {
        // A thermal-printer-style transaction stub. Flavor only.
        let n = 1000 + Int(rng.next() * 8999)
        return "NO. \(n)   BUREAU FILING"
    }
}

/// Tiny xorshift so tears and stub numbers are deterministic per title without
/// pulling in a dependency.
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    /// A value in 0.0..<1.0.
    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}
