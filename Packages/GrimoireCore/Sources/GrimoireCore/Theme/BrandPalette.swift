/// An sRGB color as 8-bit components, platform-neutral so GrimoireCore stays free of
/// AppKit and UIKit.
public struct PaletteColor: Hashable, Sendable, CustomStringConvertible {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0x1e1e2e` style literal.
    public init(hex: UInt32) {
        self.init(red: UInt8((hex >> 16) & 0xFF), green: UInt8((hex >> 8) & 0xFF), blue: UInt8(hex & 0xFF))
    }

    public var description: String {
        "#" + [red, green, blue].map { String($0, radix: 16).leftPadded(to: 2) }.joined()
    }
}

/// The color roles from the brand book, filled from Catppuccin.
///
/// Mocha is the default dark theme and Latte the default light theme (#12 exposes both
/// as built-in themes).
public struct BrandPalette: Hashable, Sendable {
    public var name: String
    public var isDark: Bool

    /// Page background (base).
    public var page: PaletteColor
    /// Sidebar (mantle).
    public var sidebar: PaletteColor
    public var crust: PaletteColor
    public var surface0: PaletteColor
    public var surface1: PaletteColor
    public var overlay0: PaletteColor
    public var overlay1: PaletteColor
    public var subtext: PaletteColor
    /// Body text.
    public var ink: PaletteColor
    /// Selection, active item, headings in Raw (mauve).
    public var magic: PaletteColor
    /// Caret, unsaved dot, list markers (peach).
    public var caret: PaletteColor
    /// Callouts (yellow).
    public var callout: PaletteColor
    /// Sparkles and MDX tags (pink).
    public var sparkle: PaletteColor
    /// The second sparkle (lavender).
    public var lavender: PaletteColor
    /// Links and keys.
    public var link: PaletteColor
    /// Strings.
    public var string: PaletteColor
    /// Quotes.
    public var quote: PaletteColor
    /// Errors.
    public var error: PaletteColor

    public static let mocha = BrandPalette(
        name: "Catppuccin Mocha", isDark: true,
        page: PaletteColor(hex: 0x1e1e2e), sidebar: PaletteColor(hex: 0x181825), crust: PaletteColor(hex: 0x11111b),
        surface0: PaletteColor(hex: 0x313244), surface1: PaletteColor(hex: 0x45475a),
        overlay0: PaletteColor(hex: 0x6c7086), overlay1: PaletteColor(hex: 0x7f849c),
        subtext: PaletteColor(hex: 0xa6adc8), ink: PaletteColor(hex: 0xcdd6f4),
        magic: PaletteColor(hex: 0xcba6f7), caret: PaletteColor(hex: 0xfab387), callout: PaletteColor(hex: 0xf9e2af),
        sparkle: PaletteColor(hex: 0xf5c2e7), lavender: PaletteColor(hex: 0xb4befe),
        link: PaletteColor(hex: 0x89b4fa), string: PaletteColor(hex: 0xa6e3a1), quote: PaletteColor(hex: 0x94e2d5),
        error: PaletteColor(hex: 0xf38ba8)
    )

    public static let latte = BrandPalette(
        name: "Catppuccin Latte", isDark: false,
        page: PaletteColor(hex: 0xeff1f5), sidebar: PaletteColor(hex: 0xe6e9ef), crust: PaletteColor(hex: 0xdce0e8),
        surface0: PaletteColor(hex: 0xccd0da), surface1: PaletteColor(hex: 0xbcc0cc),
        overlay0: PaletteColor(hex: 0x9ca0b0), overlay1: PaletteColor(hex: 0x8c8fa1),
        subtext: PaletteColor(hex: 0x6c6f85), ink: PaletteColor(hex: 0x4c4f69),
        magic: PaletteColor(hex: 0x8839ef), caret: PaletteColor(hex: 0xfe640b), callout: PaletteColor(hex: 0xdf8e1d),
        sparkle: PaletteColor(hex: 0xea76cb), lavender: PaletteColor(hex: 0x7287fd),
        link: PaletteColor(hex: 0x1e66f5), string: PaletteColor(hex: 0x40a02b), quote: PaletteColor(hex: 0x179299),
        error: PaletteColor(hex: 0xd20f39)
    )

    /// The built-in palettes, dark first.
    public static let builtIn = [mocha, latte]

    public static func `default`(dark: Bool) -> BrandPalette { dark ? mocha : latte }
}

extension String {
    fileprivate func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
