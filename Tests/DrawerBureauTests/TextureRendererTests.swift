import AppKit
import XCTest
@testable import DrawerBureau

final class TextureRendererTests: XCTestCase {
    private let slip = CGSize(width: 150, height: 84)

    /// At art.pixelScale 1 the bitmap is backed by a `size * scale` pixel
    /// buffer, the same Retina discipline the spike-board pins so the slip
    /// stays crisp.
    func testRendersBitmapAtRequestedPixelScale() throws {
        let renderer = TextureRenderer()
        var art = BureauArtTuning()
        art.pixelScale = 1
        renderer.art = art
        for scale: CGFloat in [1, 2, 3] {
            let image = renderer.image(title: "Finish the walkthrough", size: slip, scale: scale)
            let rep = try XCTUnwrap(bitmap(image), "renderer must produce a bitmap rep")
            XCTAssertEqual(rep.pixelsWide, Int(slip.width * scale))
            XCTAssertEqual(rep.pixelsHigh, Int(slip.height * scale))
        }
    }

    /// art.pixelScale divides the pixel density: the default 2 renders half
    /// the pixels each way, which is what reads as chunky Papers-Please
    /// pixels once nearest-neighbor scales it back up.
    func testPixelScaleShrinksTheBackingBuffer() throws {
        let renderer = TextureRenderer()
        XCTAssertEqual(renderer.art.pixelScale, 2, "chunky by default")
        let chunky = try XCTUnwrap(bitmap(renderer.image(title: "t", size: slip, scale: 2)))
        XCTAssertEqual(chunky.pixelsWide, Int(slip.width))
        XCTAssertEqual(chunky.pixelsHigh, Int(slip.height))

        var art = BureauArtTuning()
        art.pixelScale = 4
        renderer.art = art
        let chunkier = try XCTUnwrap(bitmap(renderer.image(title: "t", size: slip, scale: 2)))
        XCTAssertEqual(chunkier.pixelsWide, Int(slip.width / 2))
        XCTAssertEqual(chunkier.pixelsHigh, Int(slip.height / 2))
    }

    /// Setting a changed art block drops the cache (a color or font edit must
    /// re-render); setting the same art keeps it.
    func testArtChangeInvalidatesCache() {
        let renderer = TextureRenderer()
        let a = renderer.image(title: "same", size: slip, scale: 2)
        let unchanged = renderer.art
        renderer.art = unchanged // equal value: cache kept
        XCTAssertTrue(a === renderer.image(title: "same", size: slip, scale: 2))
        var art = renderer.art
        art.ink = "#000000"
        renderer.art = art // changed: cache dropped
        XCTAssertFalse(a === renderer.image(title: "same", size: slip, scale: 2))
    }

    /// A slip must carry legible dark ink, not render blank cream.
    func testRendersDarkInkPixels() throws {
        let renderer = TextureRenderer()
        let image = renderer.image(title: "Call the landlord", size: slip, scale: 2)
        let rep = try XCTUnwrap(bitmap(image))
        XCTAssertGreaterThan(
            darkInkPixelCount(rep), 20,
            "the receipt title should draw as dark ink"
        )
    }

    /// The same (text, size, scale) returns the cached image, so a settled
    /// drawer re-renders nothing (spec: re-render on edit only).
    func testCachesByTextSizeAndScale() {
        let renderer = TextureRenderer()
        let a = renderer.image(title: "same", size: slip, scale: 2)
        let b = renderer.image(title: "same", size: slip, scale: 2)
        XCTAssertTrue(a === b)
        let c = renderer.image(title: "different", size: slip, scale: 2)
        XCTAssertFalse(a === c)
    }

    /// The SpriteKit texture is nearest-filtered so it reads chunky when the
    /// physics world scales it, never smeared.
    func testTextureUsesNearestFiltering() {
        let renderer = TextureRenderer()
        let texture = renderer.texture(title: "chunky", size: slip, scale: 2)
        XCTAssertEqual(texture.filteringMode, .nearest)
    }

    /// The palette hex parser: 6 and 8 digit forms, optional #, magenta on
    /// garbage so a typo shows up in the scene instead of failing silently.
    func testPaletteHexParsing() {
        // color(_:) builds calibrated RGB, so the components read back directly.
        let c = BureauPalette.color("#E3D6B8")
        XCTAssertEqual(c.redComponent, 227.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, 214.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, 184.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.alphaComponent, 1, accuracy: 0.001)

        let bare = BureauPalette.color("E3D6B8")
        XCTAssertEqual(bare.redComponent, 227.0 / 255, accuracy: 0.001)

        let alpha = BureauPalette.color("#2926218C")
        XCTAssertEqual(alpha.alphaComponent, 140.0 / 255, accuracy: 0.001)

        XCTAssertEqual(BureauPalette.color("not a color"), .magenta)
        XCTAssertEqual(BureauPalette.color("#12345"), .magenta)
    }

    private func bitmap(_ image: NSImage) -> NSBitmapImageRep? {
        image.representations.compactMap { $0 as? NSBitmapImageRep }.first
    }

    private func darkInkPixelCount(_ rep: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { continue }
                if color.redComponent < 0.4, color.greenComponent < 0.4, color.blueComponent < 0.4 {
                    count += 1
                }
            }
        }
        return count
    }
}
