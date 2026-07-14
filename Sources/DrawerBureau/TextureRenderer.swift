import AppKit
import SpriteKit

/// The Bureau scene keeps a Papers-Please look no matter which app theme is
/// active (spec Decision 5, risk 10), so it owns its own muted palette rather
/// than reading `DrawerTheme` (which lives in the `Drawer` target anyway).
/// Gritty paper, one red accent, dark ink.
enum BureauPalette {
    static let cream = NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.77, alpha: 1)
    static let creamShade = NSColor(calibratedRed: 0.83, green: 0.78, blue: 0.66, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.13, alpha: 1)
    static let inkFaint = NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.13, alpha: 0.55)
    static let red = NSColor(calibratedRed: 0.62, green: 0.20, blue: 0.15, alpha: 1)
    /// The DONE stamp die and its ink (spec "The stamp"): a muted approval
    /// green sitting beside `red`'s POSTPONED in the same dusty register.
    static let stampGreen = NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.22, alpha: 1)
    static let drawerFloor = NSColor(calibratedRed: 0.30, green: 0.25, blue: 0.18, alpha: 1)
    static let drawerLip = NSColor(calibratedRed: 0.21, green: 0.17, blue: 0.12, alpha: 1)
    static let tray = NSColor(calibratedRed: 0.37, green: 0.32, blue: 0.24, alpha: 1)
    static let trayInk = NSColor(calibratedRed: 0.87, green: 0.83, blue: 0.73, alpha: 1)

    /// The bundled pixel face the Pixel theme ships (registered process-wide by
    /// the app at launch via `FontLoader.registerBundledFonts`). DrawerBureau
    /// cannot import `Drawer`, so the family is named directly here; a missing
    /// registration (e.g. a bare unit test) falls back to a system face so the
    /// slip still renders legible ink.
    static let pixelFamily = "Pixelify Sans"

    static func titleFont(_ size: CGFloat) -> NSFont {
        NSFont(name: pixelFamily, size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }

    static func detailFont(_ size: CGFloat) -> NSFont {
        NSFont(name: pixelFamily, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
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
    }

    private var cache: [Key: NSImage] = [:]

    /// The slip image at `size` points, backed by a `size * scale` pixel
    /// buffer. `age` is 0 (fresh off the printer) to 1 (weeks in the drawer);
    /// older paper yellows and foxes (R5 aging). Bucketed in the cache key so
    /// a slip re-renders a handful of times over its life, not per read.
    func image(title: String, details: String = "", size: CGSize, scale: CGFloat, age: Double = 0) -> NSImage {
        let bucket = Int((min(1, max(0, age)) * 4).rounded())
        let key = Key(
            title: title, details: details,
            w: Int(size.width.rounded()), h: Int(size.height.rounded()),
            scale: Int((scale * 100).rounded()),
            ageBucket: bucket
        )
        if let hit = cache[key] { return hit }
        let img = render(title: title, details: details, size: size, scale: scale, age: Double(bucket) / 4)
        cache[key] = img
        return img
    }

    /// A nearest-filtered `SKTexture` for a `ReceiptSprite`. The chunky pixel
    /// read comes from `.nearest` filtering when the physics world scales the
    /// sprite, so the slip never smears.
    func texture(title: String, details: String = "", size: CGSize, scale: CGFloat, age: Double = 0) -> SKTexture {
        let texture = SKTexture(image: image(title: title, details: details, size: size, scale: scale, age: age))
        texture.filteringMode = .nearest
        return texture
    }

    /// Drops the cache when the backing scale changes (a window moves to a
    /// different-density display), so the next render repopulates at the new
    /// scale. Called from `viewDidChangeBackingProperties` upstream.
    func invalidate() { cache.removeAll() }

    private func render(title: String, details: String, size: CGSize, scale: CGFloat, age: Double = 0) -> NSImage {
        let pxW = max(1, Int((size.width * scale).rounded()))
        let pxH = max(1, Int((size.height * scale).rounded()))
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
        draw(title: title, details: details, in: size, age: age)
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    private func draw(title: String, details: String, in size: CGSize, age: Double = 0) {
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

        // BIG readable title (legibility beats flavor at drawer scale). 15pt
        // reads big but still wraps cleanly on the narrow 96pt portrait slip.
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byWordWrapping
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: BureauPalette.titleFont(15),
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
        let detail = details.isEmpty ? defaultDetail(&rng) : details
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: BureauPalette.detailFont(8),
            .foregroundColor: BureauPalette.inkFaint,
        ]
        (detail as NSString).draw(
            at: CGPoint(x: inset, y: size.height * 0.10),
            withAttributes: detailAttrs
        )
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
