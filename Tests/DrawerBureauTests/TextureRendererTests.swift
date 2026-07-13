import AppKit
import XCTest
@testable import DrawerBureau

final class TextureRendererTests: XCTestCase {
    private let slip = CGSize(width: 150, height: 84)

    /// The bitmap is backed by a `size * scale` pixel buffer, the same Retina
    /// discipline the spike-board pins so the slip stays crisp.
    func testRendersBitmapAtRequestedPixelScale() throws {
        let renderer = TextureRenderer()
        for scale: CGFloat in [1, 2, 3] {
            let image = renderer.image(title: "Finish the walkthrough", size: slip, scale: scale)
            let rep = try XCTUnwrap(bitmap(image), "renderer must produce a bitmap rep")
            XCTAssertEqual(rep.pixelsWide, Int(slip.width * scale))
            XCTAssertEqual(rep.pixelsHigh, Int(slip.height * scale))
        }
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
