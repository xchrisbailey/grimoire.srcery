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
