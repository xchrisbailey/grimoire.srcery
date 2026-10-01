import CoreText
import Foundation
import SwiftUI

/// Geist and Geist Mono, the brand's two families, and the type scale from the brand book.
public enum BrandFont {
    public enum Style: CaseIterable, Sendable {
        /// H1 in Preview: 34 / 700, tracking -0.025em.
        case title
        /// H2 in Preview: 20 / 650.
        case heading
        /// Body text in Preview: 15.5 / 400, line height 1.7.
        case body
        /// Sidebar and window chrome: 13.5 / 500.
        case chrome
        /// Raw mode: Geist Mono 14, line height 1.9.
        case raw
        /// Paths, counts and other metadata: Geist Mono 12.
        case metadata

        public var size: CGFloat {
            switch self {
            case .title: 34
            case .heading: 20
            case .body: 15.5
            case .chrome: 13.5
            case .raw: 14
            case .metadata: 12
            }
        }

        /// Weight on the variable font's `wght` axis.
        public var weight: CGFloat {
            switch self {
            case .title: 700
            case .heading: 650
            case .body, .raw, .metadata: 400
            case .chrome: 500
            }
        }

        /// Tracking in em.
        public var tracking: CGFloat { self == .title ? -0.025 : 0 }

        /// Line height as a multiple of the font size, where the brand book sets one.
        public var lineHeight: CGFloat? {
            switch self {
            case .body: 1.7
            case .raw: 1.9
            default: nil
            }
        }

        public var isMonospaced: Bool { self == .raw || self == .metadata }
    }

    public static let family = "Geist"
    public static let monoFamily = "Geist Mono"

    /// The upright variable fonts, as loaded by `register(fontURLs:)`.
    private nonisolated(unsafe) static var variableFonts: [String: CTFontDescriptor] = [:]
    private static let lock = NSLock()

    /// Registers the bundled fonts for this process. Call once at launch with the bundle
    /// that holds the `.ttf` files (the app's main bundle).
    @discardableResult
    public static func register(from bundle: Bundle = .main) -> Bool {
        register(fontURLs: bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
    }

    @discardableResult
    public static func register(fontURLs: [URL]) -> Bool {
        let urls = fontURLs.filter { $0.lastPathComponent.hasPrefix("Geist") }
        guard !urls.isEmpty else { return false }
        lock.withLock { registeredFontURLs = urls }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        lock.withLock {
            for url in urls where !url.lastPathComponent.contains("Italic") {
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
                guard let descriptor = descriptors?.first,
                    let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
                else { continue }
                variableFonts[name] = descriptor
            }
        }
        return true
    }

    /// A Core Text font for `style` at the brand weight, falling back to the system font
    /// if Geist isn't registered.
    public static func ctFont(_ style: Style, size: CGFloat? = nil) -> CTFont {
        let size = size ?? style.size
        let familyName = style.isMonospaced ? monoFamily : family
        guard let base = lock.withLock({ variableFonts[familyName] }) else {
            return CTFontCreateUIFontForLanguage(style.isMonospaced ? .userFixedPitch : .system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        let wght = 0x7767_6874  // 'wght'
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontVariationAttribute: [wght: style.weight]] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Geist or Geist Mono at any size and weight, falling back to the system font if
    /// Geist isn't registered. `italic` slants it (Geist's italic, or a synthesized slant).
    /// `family` picks another installed family instead, as chosen in Settings.
    public static func ctFont(
        monospaced: Bool, size: CGFloat, weight: CGFloat, italic: Bool = false, family requested: String? = nil
    ) -> CTFont {
        let family = requested == (monospaced ? monoFamily : Self.family) ? nil : requested
        let key = FontKey(monospaced: monospaced, size: size, weight: weight, italic: italic, family: family)
        if let cached = lock.withLock({ fontCache[key] }) { return cached }
        if let family, let font = installedFont(family: family, size: size, weight: weight, italic: italic) {
            lock.withLock { fontCache[key] = font }
            return font
        }
        let font = makeFont(monospaced: monospaced, size: size, weight: weight, italic: italic)
        // Only cache Geist, so a fallback made before registration doesn't stick.
        lock.withLock {
            if variableFonts[Self.family] != nil, variableFonts[monoFamily] != nil { fontCache[key] = font }
        }
        return font
    }

    private struct FontKey: Hashable {
        var monospaced: Bool
        var size: CGFloat
        var weight: CGFloat
        var italic: Bool
        var family: String?
    }

    /// A font from an installed family at the nearest weight, or nil when the family
    /// isn't installed.
    private static func installedFont(family: String, size: CGFloat, weight: CGFloat, italic: Bool) -> CTFont? {
        // Core Text weights run from -1 to 1, with regular at 0 and bold at 0.4.
        let trait: CGFloat =
            switch weight {
            case ..<450: 0
            case ..<550: 0.23
            case ..<670: 0.3
            default: 0.4
            }
        var traits: [CFString: Any] = [kCTFontWeightTrait: trait]
        if italic { traits[kCTFontSymbolicTrait] = CTFontSymbolicTraits.traitItalic.rawValue }
        let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family, kCTFontTraitsAttribute: traits]
        let font = CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
        guard (CTFontCopyFamilyName(font) as String) == family else { return nil }
        return font
    }

    /// Fonts made by `ctFont(monospaced:size:weight:italic:)`; the editor asks for the
    /// same handful over and over.
    private nonisolated(unsafe) static var fontCache: [FontKey: CTFont] = [:]

    private static func makeFont(monospaced: Bool, size: CGFloat, weight: CGFloat, italic: Bool) -> CTFont {
        let familyName = monospaced ? monoFamily : family
        var font: CTFont
        if let base = lock.withLock({ variableFonts[familyName] }) {
            let wght = 0x7767_6874  // 'wght'
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(
                base, [kCTFontVariationAttribute: [wght: weight]] as CFDictionary)
            font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        } else {
            font =
                CTFontCreateUIFontForLanguage(monospaced ? .userFixedPitch : .system, size, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            if weight >= 600, let bold = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
                font = bold
            }
        }
        guard italic else { return font }
        if let slanted = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitItalic, .traitItalic) {
            return slanted
        }
        var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        return CTFontCreateCopyWithAttributes(font, size, &skew, nil)
    }

    /// The font files registered, for embedding in exported pages.
    public private(set) nonisolated(unsafe) static var registeredFontURLs: [URL] = []

    /// Whether Geist and Geist Mono have been registered.
    public static var isRegistered: Bool {
        lock.withLock { variableFonts[family] != nil && variableFonts[monoFamily] != nil }
    }
}

extension Font {
    /// A brand font for `style`: `Font.brand(.body)`.
    public static func brand(_ style: BrandFont.Style) -> Font {
        Font(BrandFont.ctFont(style))
    }
}

extension View {
    /// Applies a brand font with its tracking and line spacing.
    public func brandFont(_ style: BrandFont.Style) -> some View {
        let extraLeading = style.lineHeight.map { ($0 - 1.2) * style.size } ?? 0
        return font(.brand(style))
            .tracking(style.tracking * style.size)
            .lineSpacing(max(0, extraLeading))
    }
}
