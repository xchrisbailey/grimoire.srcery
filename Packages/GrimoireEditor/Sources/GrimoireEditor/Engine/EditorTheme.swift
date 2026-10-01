import CoreText
import GrimoireCore

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

extension PlatformColor {
    /// A brand color that follows the system appearance: Latte in light mode, Mocha in dark.
    public static func brand(_ role: KeyPath<BrandPalette, PaletteColor>) -> PlatformColor {
        let light = BrandPalette.latte[keyPath: role]
        let dark = BrandPalette.mocha[keyPath: role]
        #if os(macOS)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        }
        #else
        return UIColor { traits in UIColor(traits.userInterfaceStyle == .dark ? dark : light) }
        #endif
    }
}

/// Fonts, colors and metrics for the editor, built from the brand tokens.
public struct EditorTheme: @unchecked Sendable {
    public var bodySize: CGFloat = BrandFont.Style.body.size
    public var codeSize: CGFloat = BrandFont.Style.raw.size
    /// Line height as a multiple of the font's natural line height.
    public var lineHeightMultiple: CGFloat = 1.3
    /// Widest the text column grows before it centers in the window.
    public var maxLineWidth: CGFloat = 680
    /// How far each list level indents.
    public var listIndent: CGFloat = 22

    public var ink = PlatformColor.brand(\.ink)
    public var subtext = PlatformColor.brand(\.subtext)
    public var marker = PlatformColor.brand(\.overlay0)
    public var faint = PlatformColor.brand(\.overlay1)
    public var magic = PlatformColor.brand(\.magic)
    public var caret = PlatformColor.brand(\.caret)
    public var link = PlatformColor.brand(\.link)
    public var quote = PlatformColor.brand(\.quote)
    public var sparkle = PlatformColor.brand(\.sparkle)
    public var codeBackground = PlatformColor.brand(\.surface0)
    public var surface = PlatformColor.brand(\.surface1)
    public var page = PlatformColor.brand(\.page)

    public init() {}

    public func font(size: CGFloat? = nil, weight: CGFloat = 400, italic: Bool = false, monospaced: Bool = false)
        -> PlatformFont
    {
        BrandFont.ctFont(monospaced: monospaced, size: size ?? bodySize, weight: weight, italic: italic)
            as PlatformFont
    }

    public var body: PlatformFont { font() }
    public var code: PlatformFont { font(size: codeSize, monospaced: true) }
    public var inlineCode: PlatformFont { font(size: bodySize * 0.9, monospaced: true) }
    public var metadata: PlatformFont { font(size: BrandFont.Style.metadata.size, monospaced: true) }

    public func heading(_ level: Int) -> PlatformFont {
        switch level {
        case 1: font(size: BrandFont.Style.title.size, weight: BrandFont.Style.title.weight)
        case 2: font(size: BrandFont.Style.heading.size, weight: BrandFont.Style.heading.weight)
        case 3: font(size: 17, weight: 650)
        default: font(weight: 650)
        }
    }

    /// Markers off the caret's block are shrunk to nothing and made clear, so they take no
    /// room but keep their place in the text.
    public static var hiddenFont: PlatformFont {
        BrandFont.ctFont(monospaced: false, size: 0.01, weight: 400) as PlatformFont
    }
}
