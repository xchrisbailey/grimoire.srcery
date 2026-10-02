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
    /// A color that follows the appearance: `light` in light mode, `dark` in dark mode.
    public static func dynamic(light: PaletteColor, dark: PaletteColor) -> PlatformColor {
        if light == dark { return PlatformColor(light) }
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

/// Fonts, colors and metrics for the editor: the light and dark themes, and the sizes
/// Settings controls.
public struct EditorTheme: Equatable, @unchecked Sendable {
    /// The theme drawn in light mode.
    public var light: Theme
    /// The theme drawn in dark mode.
    public var dark: Theme
    /// Which of the two the view is showing now. Colors follow the appearance by
    /// themselves; this picks font styles (bold, italic) that a theme sets per token.
    public var isDark = false

    public var bodySize: CGFloat = BrandFont.Style.body.size
    public var codeSize: CGFloat = BrandFont.Style.raw.size
    /// Line height as a multiple of the font's natural line height.
    public var lineHeightMultiple: CGFloat = 1.3
    /// Widest the text column grows before it centers in the window.
    public var maxLineWidth: CGFloat = 680
    /// How far each list level indents.
    public var listIndent: CGFloat = 22
    /// Raw mode's line height, as a multiple of Geist Mono's natural height (1.9 in the
    /// brand book, measured in font sizes).
    public var rawLineHeightMultiple: CGFloat = 1.45
    /// The prose font's family; nil for Geist.
    public var proseFamily: String?
    /// The code and Raw font's family; nil for Geist Mono.
    public var codeFamily: String?
    /// Columns between tab stops in Raw and code blocks.
    public var tabWidth = 4

    public init(light: Theme = .latte, dark: Theme = .mocha) {
        self.light = light
        self.dark = dark
    }

    /// The theme for the current appearance.
    public var current: Theme { isDark ? dark : light }

    /// A brand role, following the appearance.
    public func color(_ role: KeyPath<BrandPalette, PaletteColor>) -> PlatformColor {
        .dynamic(light: light.palette[keyPath: role], dark: dark.palette[keyPath: role])
    }

    public func editorColor(_ role: KeyPath<EditorColors, PaletteColor>) -> PlatformColor {
        .dynamic(light: light.editor[keyPath: role], dark: dark.editor[keyPath: role])
    }

    // MARK: - Roles

    public var ink: PlatformColor { color(\.ink) }
    public var subtext: PlatformColor { color(\.subtext) }
    public var marker: PlatformColor { color(\.overlay0) }
    public var faint: PlatformColor { color(\.overlay1) }
    public var magic: PlatformColor { color(\.magic) }
    public var caret: PlatformColor { color(\.caret) }
    public var link: PlatformColor { color(\.link) }
    public var quote: PlatformColor { color(\.quote) }
    public var sparkle: PlatformColor { color(\.sparkle) }
    public var codeBackground: PlatformColor { color(\.surface0) }
    public var surface: PlatformColor { color(\.surface1) }
    public var page: PlatformColor { color(\.page) }
    public var string: PlatformColor { color(\.string) }
    public var attribute: PlatformColor { color(\.callout) }
    public var selection: PlatformColor { editorColor(\.selection) }
    public var insertionPoint: PlatformColor { editorColor(\.caret) }
    public var lineHighlight: PlatformColor { editorColor(\.lineHighlight) }

    // MARK: - Tokens

    /// How `token` draws in Preview or Raw. Its color follows the appearance; a token
    /// one theme colors and the other doesn't falls back to that theme's ink.
    public func token(_ token: MarkdownToken, raw: Bool) -> ResolvedStyle {
        resolve(light.style(token, raw: raw), dark.style(token, raw: raw))
    }

    public func code(_ token: CodeToken) -> ResolvedStyle {
        resolve(light.style(token), dark.style(token))
    }

    private func resolve(_ lightStyle: TokenStyle, _ darkStyle: TokenStyle) -> ResolvedStyle {
        let style = isDark ? darkStyle : lightStyle
        var resolved = ResolvedStyle(
            bold: style.bold, italic: style.italic, underline: style.underline == true,
            strikethrough: style.strikethrough == true)
        if lightStyle.color != nil || darkStyle.color != nil {
            resolved.color = .dynamic(
                light: lightStyle.color ?? light.palette.ink, dark: darkStyle.color ?? dark.palette.ink)
        }
        if lightStyle.background != nil || darkStyle.background != nil {
            resolved.background = .dynamic(
                light: lightStyle.background ?? light.palette.page, dark: darkStyle.background ?? dark.palette.page)
        }
        return resolved
    }

    /// A token's style as text attributes.
    public struct ResolvedStyle {
        public var color: PlatformColor?
        public var background: PlatformColor?
        /// Nil leaves the weight as the surrounding text has it.
        public var bold: Bool?
        public var italic: Bool?
        public var underline: Bool
        public var strikethrough: Bool

        /// The color, underline and strikethrough as attributes. Fonts are set separately,
        /// since weight and slant combine with the text around them.
        public var attributes: [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let color { attributes[.foregroundColor] = color }
            if let background { attributes[.backgroundColor] = background }
            if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return attributes
        }
    }

    // MARK: - Fonts

    public func font(size: CGFloat? = nil, weight: CGFloat = 400, italic: Bool = false, monospaced: Bool = false)
        -> PlatformFont
    {
        BrandFont.ctFont(
            monospaced: monospaced, size: size ?? bodySize, weight: weight, italic: italic,
            family: monospaced ? codeFamily : proseFamily) as PlatformFont
    }

    /// Sets the prose line height from a CSS-style multiple of the font size (the brand's
    /// 1.7). TextKit measures from the font's own line height, which for Geist is about
    /// 1.3 times its size.
    public mutating func setLineHeight(_ multiple: CGFloat) {
        lineHeightMultiple = multiple * 1.3 / 1.7
    }

    public var body: PlatformFont { font() }
    public var code: PlatformFont { font(size: codeSize, monospaced: true) }

    /// The distance between tab stops: `tabWidth` spaces of the code font.
    public var tabInterval: CGFloat {
        let space = (" " as NSString).size(withAttributes: [.font: code]).width
        return space * CGFloat(max(1, tabWidth))
    }
    public var inlineCode: PlatformFont { font(size: bodySize * 0.9, monospaced: true) }
    public var metadata: PlatformFont { font(size: BrandFont.Style.metadata.size, monospaced: true) }

    /// Headings scale with the body size: 34, 20 and 17 points beside the default 15.5.
    public func heading(_ level: Int) -> PlatformFont {
        let style = token(.heading(level), raw: false)
        let italic = style.italic == true
        let scale = bodySize / BrandFont.Style.body.size
        switch level {
        case 1:
            let weight = style.bold == false ? 500 : BrandFont.Style.title.weight
            return font(size: (BrandFont.Style.title.size * scale).rounded(), weight: weight, italic: italic)
        case 2:
            let weight = style.bold == false ? 500 : BrandFont.Style.heading.weight
            return font(size: (BrandFont.Style.heading.size * scale).rounded(), weight: weight, italic: italic)
        case 3: return font(size: (17 * scale).rounded(), weight: style.bold == false ? 500 : 650, italic: italic)
        default: return font(weight: style.bold == false ? 500 : 650, italic: italic)
        }
    }

    /// Markers off the caret's block are shrunk to nothing and made clear, so they take no
    /// room but keep their place in the text.
    public static var hiddenFont: PlatformFont {
        BrandFont.ctFont(monospaced: false, size: 0.01, weight: 400) as PlatformFont
    }
}
