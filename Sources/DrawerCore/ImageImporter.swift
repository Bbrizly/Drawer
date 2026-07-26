import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves dropped or pasted images into the board's media folder and produces
/// downsampled thumbnails for display. Downsampling (ImageIO) is the rule that
/// keeps the canvas fast: a 4K screenshot is never drawn at 4K, only at the
/// size it appears on screen. Pure and off-the-main-thread friendly.
public enum ImageImporter {
    public struct Imported: Equatable, Sendable {
        public let relativeFile: String   // relative to the Ideas/ directory
        public let naturalWidth: Double
        public let naturalHeight: Double
    }

    public enum ImportError: Error { case undecodable }

    /// Persist raw image bytes into `mediaDirectory`, keeping the source format.
    /// Returns the relative path and the image's natural pixel size.
    public static func persist(_ data: Data, into mediaDirectory: URL) throws -> Imported {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { throw ImportError.undecodable }

        let w = (props[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Double) ?? 0
        guard w > 0, h > 0 else { throw ImportError.undecodable }

        let ext = fileExtension(for: src)
        let name = SnapshotStore.sha256Hex(data) + "." + ext
        let url = mediaDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return Imported(relativeFile: "media/" + name, naturalWidth: w, naturalHeight: h)
    }

    /// Decode a thumbnail no larger than `maxPixelSize` on its longest edge.
    /// Call off the main thread; hand the result back to set as layer.contents.
    public static func downsample(fileURL: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, srcOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    // MARK: helpers

    private static func fileExtension(for src: CGImageSource) -> String {
        if let uti = CGImageSourceGetType(src) as String?,
           let ext = UTType(uti)?.preferredFilenameExtension {
            return ext
        }
        return "png"
    }
}
