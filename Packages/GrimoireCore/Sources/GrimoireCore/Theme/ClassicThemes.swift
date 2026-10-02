import Foundation

/// Well-known editor themes, built in so they're one click away instead of a VS Code
/// import. Each fills the brand roles from its own published palette by hue: its purple
/// is `magic`, its orange `caret`, its blue `link` and so on, so code and markdown pick
/// up the theme's colors the same way an imported theme's would.
extension Theme {
    public static let frappe = classic("catppuccin-frappe", .frappe)
    public static let macchiato = classic("catppuccin-macchiato", .macchiato)
    public static let dracula = classic("dracula", .dracula)
    public static let githubDark = classic("github-dark", .githubDark)
    public static let githubLight = classic("github-light", .githubLight)
    public static let gruvboxDark = classic("gruvbox-dark", .gruvboxDark)
    public static let gruvboxLight = classic("gruvbox-light", .gruvboxLight)
    public static let nord = classic("nord", .nord)
    public static let oneDark = classic("one-dark", .oneDark)
    public static let rosePine = classic("rose-pine", .rosePine)
    public static let solarizedDark = classic("solarized-dark", .solarizedDark)
    public static let solarizedLight = classic("solarized-light", .solarizedLight)
    public static let tokyoNight = classic("tokyo-night", .tokyoNight)

    /// The rest of Catppuccin, then the others by name.
    static let classics = [
        frappe, macchiato, dracula, githubDark, githubLight, gruvboxDark, gruvboxLight, nord, oneDark, rosePine,
        solarizedDark, solarizedLight, tokyoNight,
    ]

    private static func classic(_ id: String, _ palette: BrandPalette) -> Theme {
        Theme(id: id, name: palette.name, isDark: palette.isDark, origin: .builtIn, palette: palette)
    }
}

extension BrandPalette {
    static let frappe = palette(
        "Catppuccin Frappé", dark: true,
        page: 0x303446, sidebar: 0x292c3c, crust: 0x232634, surface0: 0x414559, surface1: 0x51576d,
        overlay0: 0x737994, overlay1: 0x838ba7, subtext: 0xa5adce, ink: 0xc6d0f5,
        magic: 0xca9ee6, caret: 0xef9f76, callout: 0xe5c890, sparkle: 0xf4b8e4, lavender: 0xbabbf1,
        link: 0x8caaee, string: 0xa6d189, quote: 0x81c8be, error: 0xe78284)

    static let macchiato = palette(
        "Catppuccin Macchiato", dark: true,
        page: 0x24273a, sidebar: 0x1e2030, crust: 0x181926, surface0: 0x363a4f, surface1: 0x494d64,
        overlay0: 0x6e738d, overlay1: 0x8087a2, subtext: 0xa5adcb, ink: 0xcad3f5,
        magic: 0xc6a0f6, caret: 0xf5a97f, callout: 0xeed49f, sparkle: 0xf5bde6, lavender: 0xb7bdf8,
        link: 0x8aadf4, string: 0xa6da95, quote: 0x8bd5ca, error: 0xed8796)

    static let dracula = palette(
        "Dracula", dark: true,
        page: 0x282a36, sidebar: 0x21222c, crust: 0x191a21, surface0: 0x343746, surface1: 0x44475a,
        overlay0: 0x6272a4, overlay1: 0x7b88c0, subtext: 0xc0c4d6, ink: 0xf8f8f2,
        magic: 0xbd93f9, caret: 0xffb86c, callout: 0xf1fa8c, sparkle: 0xff79c6, lavender: 0xd6acff,
        link: 0x8be9fd, string: 0x50fa7b, quote: 0xa4ffff, error: 0xff5555)

    static let githubDark = palette(
        "GitHub Dark", dark: true,
        page: 0x0d1117, sidebar: 0x010409, crust: 0x000000, surface0: 0x21262d, surface1: 0x30363d,
        overlay0: 0x6e7681, overlay1: 0x8b949e, subtext: 0xb1bac4, ink: 0xe6edf3,
        magic: 0xd2a8ff, caret: 0xffa657, callout: 0xe3b341, sparkle: 0xf778ba, lavender: 0xa5d6ff,
        link: 0x58a6ff, string: 0x7ee787, quote: 0x56d4dd, error: 0xf85149)

    static let githubLight = palette(
        "GitHub Light", dark: false,
        page: 0xffffff, sidebar: 0xf6f8fa, crust: 0xeaeef2, surface0: 0xd1d9e0, surface1: 0xafb8c1,
        overlay0: 0x8c959f, overlay1: 0x6e7781, subtext: 0x59636e, ink: 0x1f2328,
        magic: 0x8250df, caret: 0xbc4c00, callout: 0x9a6700, sparkle: 0xbf3989, lavender: 0x6639ba,
        link: 0x0969da, string: 0x116329, quote: 0x1b7c83, error: 0xcf222e)

    static let gruvboxDark = palette(
        "Gruvbox Dark", dark: true,
        page: 0x282828, sidebar: 0x1d2021, crust: 0x161819, surface0: 0x3c3836, surface1: 0x504945,
        overlay0: 0x7c6f64, overlay1: 0x928374, subtext: 0xbdae93, ink: 0xebdbb2,
        magic: 0xd3869b, caret: 0xfe8019, callout: 0xfabd2f, sparkle: 0xd3869b, lavender: 0x83a598,
        link: 0x83a598, string: 0xb8bb26, quote: 0x8ec07c, error: 0xfb4934)

    static let gruvboxLight = palette(
        "Gruvbox Light", dark: false,
        page: 0xfbf1c7, sidebar: 0xf2e5bc, crust: 0xebdbb2, surface0: 0xd5c4a1, surface1: 0xbdae93,
        overlay0: 0xa89984, overlay1: 0x928374, subtext: 0x665c54, ink: 0x3c3836,
        magic: 0x8f3f71, caret: 0xaf3a03, callout: 0xb57614, sparkle: 0x8f3f71, lavender: 0x076678,
        link: 0x076678, string: 0x79740e, quote: 0x427b58, error: 0x9d0006)

    static let nord = palette(
        "Nord", dark: true,
        page: 0x2e3440, sidebar: 0x2b303b, crust: 0x242933, surface0: 0x3b4252, surface1: 0x434c5e,
        overlay0: 0x4c566a, overlay1: 0x616e88, subtext: 0xaeb7c6, ink: 0xd8dee9,
        magic: 0x88c0d0, caret: 0xd08770, callout: 0xebcb8b, sparkle: 0xb48ead, lavender: 0x5e81ac,
        link: 0x81a1c1, string: 0xa3be8c, quote: 0x8fbcbb, error: 0xbf616a)

    static let oneDark = palette(
        "One Dark", dark: true,
        page: 0x282c34, sidebar: 0x21252b, crust: 0x181a1f, surface0: 0x3e4451, surface1: 0x4b5263,
        overlay0: 0x5c6370, overlay1: 0x7f848e, subtext: 0x9da5b4, ink: 0xabb2bf,
        magic: 0xc678dd, caret: 0xd19a66, callout: 0xe5c07b, sparkle: 0xe06c75, lavender: 0xe06c75,
        link: 0x61afef, string: 0x98c379, quote: 0x56b6c2, error: 0xbe5046)

    static let rosePine = palette(
        "Rosé Pine", dark: true,
        page: 0x191724, sidebar: 0x1f1d2e, crust: 0x13111c, surface0: 0x26233a, surface1: 0x403d52,
        overlay0: 0x6e6a86, overlay1: 0x817c9c, subtext: 0x908caa, ink: 0xe0def4,
        magic: 0xc4a7e7, caret: 0xebbcba, callout: 0xf6c177, sparkle: 0xeb6f92, lavender: 0xc4a7e7,
        link: 0x9ccfd8, string: 0xf6c177, quote: 0x9ccfd8, error: 0xeb6f92)

    static let solarizedDark = palette(
        "Solarized Dark", dark: true,
        page: 0x002b36, sidebar: 0x00212b, crust: 0x001a22, surface0: 0x073642, surface1: 0x1a4552,
        overlay0: 0x586e75, overlay1: 0x657b83, subtext: 0x93a1a1, ink: 0x839496,
        magic: 0x6c71c4, caret: 0xcb4b16, callout: 0xb58900, sparkle: 0xd33682, lavender: 0x6c71c4,
        link: 0x268bd2, string: 0x859900, quote: 0x2aa198, error: 0xdc322f)

    static let solarizedLight = palette(
        "Solarized Light", dark: false,
        page: 0xfdf6e3, sidebar: 0xeee8d5, crust: 0xe4ddc8, surface0: 0xddd6c1, surface1: 0xcfc8b3,
        overlay0: 0x93a1a1, overlay1: 0x839496, subtext: 0x657b83, ink: 0x586e75,
        magic: 0x6c71c4, caret: 0xcb4b16, callout: 0xb58900, sparkle: 0xd33682, lavender: 0x6c71c4,
        link: 0x268bd2, string: 0x859900, quote: 0x2aa198, error: 0xdc322f)

    static let tokyoNight = palette(
        "Tokyo Night", dark: true,
        page: 0x1a1b26, sidebar: 0x16161e, crust: 0x101014, surface0: 0x292e42, surface1: 0x3b4261,
        overlay0: 0x565f89, overlay1: 0x737aa2, subtext: 0xa9b1d6, ink: 0xc0caf5,
        magic: 0xbb9af7, caret: 0xff9e64, callout: 0xe0af68, sparkle: 0xf7768e, lavender: 0x9d7cd8,
        link: 0x7aa2f7, string: 0x9ece6a, quote: 0x73daca, error: 0xdb4b4b)

    // swiftlint:disable:next function_parameter_count
    private static func palette(
        _ name: String, dark: Bool, page: UInt32, sidebar: UInt32, crust: UInt32, surface0: UInt32,
        surface1: UInt32, overlay0: UInt32, overlay1: UInt32, subtext: UInt32, ink: UInt32, magic: UInt32,
        caret: UInt32, callout: UInt32, sparkle: UInt32, lavender: UInt32, link: UInt32, string: UInt32,
        quote: UInt32, error: UInt32
    ) -> BrandPalette {
        BrandPalette(
            name: name, isDark: dark, page: PaletteColor(hex: page), sidebar: PaletteColor(hex: sidebar),
            crust: PaletteColor(hex: crust), surface0: PaletteColor(hex: surface0),
            surface1: PaletteColor(hex: surface1), overlay0: PaletteColor(hex: overlay0),
            overlay1: PaletteColor(hex: overlay1), subtext: PaletteColor(hex: subtext), ink: PaletteColor(hex: ink),
            magic: PaletteColor(hex: magic), caret: PaletteColor(hex: caret), callout: PaletteColor(hex: callout),
            sparkle: PaletteColor(hex: sparkle), lavender: PaletteColor(hex: lavender), link: PaletteColor(hex: link),
            string: PaletteColor(hex: string), quote: PaletteColor(hex: quote), error: PaletteColor(hex: error))
    }
}
