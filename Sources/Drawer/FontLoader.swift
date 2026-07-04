import CoreText
import Foundation
import SwiftUI

/// Registers bundled fonts so art themes can name them. TTFs ship as package
/// resources (see Package.swift). Drop `tahoma.ttf` into Resources/Fonts for
/// the Windows XP theme; it is not redistributed here.
enum FontLoader {
    /// Family name SwiftUI asks for: `Font.custom("Pixelify Sans", size:)`.
    static let pixelFamily = "Pixelify Sans"
    /// Luna UI face. Bundled Tahoma wins; otherwise Tahoma/Arial on the system.
    static let xpFamily = "Tahoma"

    private static var didRegister = false
    private static var resolvedXPFamily: String?

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        guard let dir = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
              )
        else {
            resolvedXPFamily = pickXPFamily()
            return
        }
        for url in urls where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        resolvedXPFamily = pickXPFamily()
    }

    /// SwiftUI font for the XP skin.
    static func xpFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if !didRegister { registerBundledFonts() }
        let name = resolvedXPFamily ?? pickXPFamily()
        return Font.custom(name, size: size).weight(weight)
    }

    /// AppKit font for the layer-backed idea board.
    static func xpNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if !didRegister { registerBundledFonts() }
        let name = resolvedXPFamily ?? pickXPFamily()
        let font = NSFont(name: name, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
        switch weight {
        case .bold, .heavy, .black, .semibold:
            return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        default:
            return font
        }
    }

    static func xpFontIsAvailable() -> Bool {
        if !didRegister { registerBundledFonts() }
        return NSFontManager.shared.availableFontFamilies.contains { family in
            family.localizedCaseInsensitiveContains("tahoma")
        }
    }

    private static func pickXPFamily() -> String {
        let families = NSFontManager.shared.availableFontFamilies
        if families.contains(xpFamily) { return xpFamily }
        if families.contains("Tahoma") { return "Tahoma" }
        // Arial ships on macOS and matches Tahoma metrics closely enough.
        if families.contains("Arial") { return "Arial" }
        return xpFamily
    }
}
