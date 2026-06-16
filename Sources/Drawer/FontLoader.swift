import CoreText
import Foundation

/// Registers the bundled pixel font so the Pixel theme can name it. The TTF
/// ships as a package resource (see Package.swift), so it loads the same way
/// from `swift run` and from the assembled .app, as long as the resource
/// bundle sits next to the binary or in the app's Resources.
enum FontLoader {
    /// Family name SwiftUI asks for: `Font.custom("Pixelify Sans", size:)`.
    static let pixelFamily = "Pixelify Sans"

    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
              )
        else {
            return
        }
        for url in urls where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
