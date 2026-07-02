import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DrawerCore

final class ImageImporterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pngData(width: Int, height: Int) -> Data {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testPersistWritesFileAndReturnsNaturalSize() throws {
        let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        let data = pngData(width: 200, height: 120)
        let imported = try ImageImporter.persist(data, into: mediaDir, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(imported.naturalWidth, 200, accuracy: 0.001)
        XCTAssertEqual(imported.naturalHeight, 120, accuracy: 0.001)
        XCTAssertTrue(imported.relativeFile.hasPrefix("media/"))

        let fileURL = dir.appendingPathComponent(imported.relativeFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDownsampleClampsLongestEdge() throws {
        let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        let data = pngData(width: 1000, height: 500)
        let imported = try ImageImporter.persist(data, into: mediaDir, now: Date())
        let url = dir.appendingPathComponent(imported.relativeFile)

        let thumb = ImageImporter.downsample(fileURL: url, maxPixelSize: 100)
        XCTAssertNotNil(thumb)
        XCTAssertEqual(max(thumb!.width, thumb!.height), 100)
    }

    func testPersistRejectsGarbage() {
        let mediaDir = dir.appendingPathComponent("media", isDirectory: true)
        let junk = Data([0, 1, 2, 3, 4, 5])
        XCTAssertThrowsError(try ImageImporter.persist(junk, into: mediaDir, now: Date()))
    }
}
