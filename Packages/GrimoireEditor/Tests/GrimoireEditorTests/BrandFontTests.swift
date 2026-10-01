import CoreText
import Foundation
import Testing

@testable import GrimoireEditor

@Suite(.serialized) struct BrandFontTests {
    /// The repo's bundled fonts, so the test doesn't need an app bundle.
    static func registerRepoFonts() {
        let fonts = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../Resources/Fonts").standardized
        let urls = ((try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "ttf" }
        BrandFont.register(fontURLs: urls)
    }

    @Test func stylesResolveToGeistAtBrandWeights() {
        Self.registerRepoFonts()
        #expect(BrandFont.isRegistered)
        for style in BrandFont.Style.allCases {
            let font = BrandFont.ctFont(style)
            let family = CTFontCopyFamilyName(font) as String
            #expect(family == (style.isMonospaced ? "Geist Mono" : "Geist"), "\(style)")
            #expect(CTFontGetSize(font) == style.size)
            let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
            // Core Text leaves the axis out when it sits at the font's default, 400.
            let weight = variation?[NSNumber(value: 0x7767_6874)]?.doubleValue ?? 400
            #expect(weight == Double(style.weight), "\(style)")
        }
    }

    @Test func typeScaleMatchesTheBrandBook() {
        #expect(BrandFont.Style.title.size == 34)
        #expect(BrandFont.Style.title.weight == 700)
        #expect(BrandFont.Style.heading.weight == 650)
        #expect(BrandFont.Style.body.lineHeight == 1.7)
        #expect(BrandFont.Style.raw.lineHeight == 1.9)
    }
}
