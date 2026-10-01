import Foundation

/// A complete look for the app and editor: the brand color roles, the editor's own UI
/// colors, and how each piece of markdown (and code, for #13) is drawn.
///
/// Fonts aren't part of a theme; they're set in Settings.
public struct Theme: Codable, Identifiable, Hashable, Sendable {
    public enum Origin: Codable, Hashable, Sendable {
        case builtIn
        /// Imported from a VS Code theme file, named here for the theme list.
        case imported(fileName: String)
    }

    public var id: String
    public var name: String
    public var isDark: Bool
    public var origin: Origin
    /// The brand roles the app chrome and editor draw with.
    public var palette: BrandPalette
    public var editor: EditorColors
    /// Markdown in Preview, where markers hide and text is set as prose.
    public var preview: [MarkdownToken: TokenStyle]
    /// Markdown in Raw, the source with syntax colors.
    public var raw: [MarkdownToken: TokenStyle]
    /// Code inside fenced blocks.
    public var code: [CodeToken: TokenStyle]

    public init(
        id: String, name: String, isDark: Bool, origin: Origin, palette: BrandPalette, editor: EditorColors? = nil,
        preview: [MarkdownToken: TokenStyle]? = nil, raw: [MarkdownToken: TokenStyle]? = nil,
        code: [CodeToken: TokenStyle]? = nil
    ) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.origin = origin
        self.palette = palette
        self.editor = editor ?? EditorColors(palette: palette)
        self.preview = preview ?? MarkdownToken.previewStyles(palette)
        self.raw = raw ?? MarkdownToken.rawStyles(palette)
        self.code = code ?? CodeToken.styles(palette)
    }

    public static let mocha = Theme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isDark: true, origin: .builtIn, palette: .mocha)
    public static let latte = Theme(
        id: "catppuccin-latte", name: "Catppuccin Latte", isDark: false, origin: .builtIn, palette: .latte)

    /// The built-in pair, dark first.
    public static let builtIn = [mocha, latte]

    public static func `default`(dark: Bool) -> Theme { dark ? mocha : latte }

    public func style(_ token: MarkdownToken, raw isRaw: Bool) -> TokenStyle {
        (isRaw ? raw : preview)[token] ?? TokenStyle()
    }

    public func style(_ token: CodeToken) -> TokenStyle {
        code[token] ?? TokenStyle()
    }
}

/// Editor colors that aren't brand roles.
public struct EditorColors: Codable, Hashable, Sendable {
    /// Behind selected text, already laid over the page.
    public var selection: PaletteColor
    public var caret: PaletteColor
    /// Behind the caret's line in Raw.
    public var lineHighlight: PaletteColor
    /// Line numbers and other gutter text.
    public var gutter: PaletteColor
    public var border: PaletteColor

    public init(
        selection: PaletteColor, caret: PaletteColor, lineHighlight: PaletteColor, gutter: PaletteColor,
        border: PaletteColor
    ) {
        self.selection = selection
        self.caret = caret
        self.lineHighlight = lineHighlight
        self.gutter = gutter
        self.border = border
    }

    /// The brand's choices: mauve selection, peach caret, a faint line highlight.
    public init(palette: BrandPalette) {
        self.init(
            selection: palette.page.mixed(with: palette.magic, amount: 0.25), caret: palette.caret,
            lineHighlight: palette.page.mixed(with: palette.ink, amount: 0.06), gutter: palette.overlay0,
            border: palette.surface0)
    }
}

/// How one kind of text draws. Nil fields fall back to the surrounding text.
public struct TokenStyle: Codable, Hashable, Sendable {
    public var color: PaletteColor?
    public var background: PaletteColor?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?

    public init(
        color: PaletteColor? = nil, background: PaletteColor? = nil, bold: Bool? = nil, italic: Bool? = nil,
        underline: Bool? = nil, strikethrough: Bool? = nil
    ) {
        self.color = color
        self.background = background
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// `other`'s settings on top of these.
    public func merged(with other: TokenStyle) -> TokenStyle {
        TokenStyle(
            color: other.color ?? color, background: other.background ?? background, bold: other.bold ?? bold,
            italic: other.italic ?? italic, underline: other.underline ?? underline,
            strikethrough: other.strikethrough ?? strikethrough)
    }
}

/// The pieces of markdown a theme styles.
public enum MarkdownToken: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case heading1, heading2, heading3, heading4, heading5, heading6
    case bold, italic, strikethrough
    case inlineCode
    /// Code block text, and its background.
    case codeBlock
    /// The fence lines around a code block.
    case codeFence
    case link
    /// A link's destination, `(url)`.
    case linkDestination
    case quote
    /// `- `, `1. ` and `[ ]`.
    case listMarker
    /// `**`, `_`, `~~` and `` ` ``.
    case emphasisMarker
    /// Other syntax: `#`, `>`, brackets, table pipes.
    case syntaxMarker
    /// The `---` lines around frontmatter.
    case frontmatter
    case frontmatterKey
    case frontmatterValue
    case html
    /// MDX tags and `import` / `export`.
    case mdx
    case mdxAttribute
    case mdxString

    public static func heading(_ level: Int) -> MarkdownToken {
        [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6][min(max(level, 1), 6) - 1]
    }

    /// Preview's look from the brand book: ink headings, blue links, peach list markers,
    /// quiet markers on the caret's block.
    static func previewStyles(_ palette: BrandPalette) -> [MarkdownToken: TokenStyle] {
        [
            .strikethrough: TokenStyle(color: palette.subtext, strikethrough: true),
            .inlineCode: TokenStyle(background: palette.surface0),
            .codeBlock: TokenStyle(color: palette.ink, background: palette.surface0),
            .codeFence: TokenStyle(color: palette.overlay0),
            .link: TokenStyle(color: palette.link),
            .linkDestination: TokenStyle(color: palette.overlay0),
            .quote: TokenStyle(color: palette.subtext),
            .listMarker: TokenStyle(color: palette.caret),
            .emphasisMarker: TokenStyle(color: palette.overlay0),
            .syntaxMarker: TokenStyle(color: palette.overlay0),
            .frontmatter: TokenStyle(color: palette.overlay1),
            .frontmatterKey: TokenStyle(color: palette.overlay1),
            .frontmatterValue: TokenStyle(color: palette.overlay1),
            .html: TokenStyle(color: palette.subtext),
            .mdx: TokenStyle(color: palette.sparkle),
            .mdxAttribute: TokenStyle(color: palette.callout),
            .mdxString: TokenStyle(color: palette.string),
        ]
    }

    /// Raw's look from the brand book: mauve bold headings, peach list and emphasis
    /// markers, blue keys, green strings, teal quotes, pink MDX, yellow attributes, dim
    /// link punctuation.
    static func rawStyles(_ palette: BrandPalette) -> [MarkdownToken: TokenStyle] {
        var styles: [MarkdownToken: TokenStyle] = [
            .strikethrough: TokenStyle(strikethrough: true),
            .inlineCode: TokenStyle(color: palette.string),
            .codeBlock: TokenStyle(color: palette.ink),
            .codeFence: TokenStyle(color: palette.overlay1),
            .link: TokenStyle(color: palette.link),
            .linkDestination: TokenStyle(color: palette.quote),
            .quote: TokenStyle(color: palette.quote),
            .listMarker: TokenStyle(color: palette.caret),
            .emphasisMarker: TokenStyle(color: palette.caret),
            .syntaxMarker: TokenStyle(color: palette.overlay0),
            .frontmatter: TokenStyle(color: palette.overlay1),
            .frontmatterKey: TokenStyle(color: palette.link),
            .frontmatterValue: TokenStyle(color: palette.string),
            .html: TokenStyle(color: palette.subtext),
            .mdx: TokenStyle(color: palette.sparkle),
            .mdxAttribute: TokenStyle(color: palette.callout),
            .mdxString: TokenStyle(color: palette.string),
        ]
        for level in 1...6 { styles[.heading(level)] = TokenStyle(color: palette.magic, bold: true) }
        return styles
    }
}

/// The kinds of code a highlighter reports, named like tree-sitter captures.
public enum CodeToken: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case keyword, string, comment, function, type, number, constant, variable, property, `operator`
    case punctuation, tag, attribute, escape, builtin

    /// Catppuccin's code colors: mauve keywords, green strings, blue functions, yellow
    /// types, peach numbers.
    static func styles(_ palette: BrandPalette) -> [CodeToken: TokenStyle] {
        [
            .keyword: TokenStyle(color: palette.magic),
            .string: TokenStyle(color: palette.string),
            .comment: TokenStyle(color: palette.overlay1, italic: true),
            .function: TokenStyle(color: palette.link),
            .type: TokenStyle(color: palette.callout),
            .number: TokenStyle(color: palette.caret),
            .constant: TokenStyle(color: palette.caret),
            .variable: TokenStyle(color: palette.ink),
            .property: TokenStyle(color: palette.lavender),
            .operator: TokenStyle(color: palette.quote),
            .punctuation: TokenStyle(color: palette.overlay1),
            .tag: TokenStyle(color: palette.link),
            .attribute: TokenStyle(color: palette.callout),
            .escape: TokenStyle(color: palette.sparkle),
            .builtin: TokenStyle(color: palette.error),
        ]
    }
}
