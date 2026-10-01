import Foundation

/// Turns VS Code theme files into Grimoire themes: "Borrow a look from VS Code".
public enum ThemeImport {
    /// The themes in a `.json` theme file or a `.vsix` extension. `load` reads files a
    /// `.json` theme refers to by relative path (an `include`d parent); under the sandbox
    /// it usually can't, and the missing settings fall back to Catppuccin.
    public static func themes(from url: URL) throws -> [Theme] {
        let fileName = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeImportError.unreadable(fileName)
        }
        if url.pathExtension.lowercased() == "vsix" || data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return try themes(fromExtension: data, fileName: fileName)
        }
        let folder = url.deletingLastPathComponent()
        let theme = try VSCodeTheme(
            data: data, fallbackName: url.deletingPathExtension().lastPathComponent,
            load: { try? Data(contentsOf: folder.appending(path: $0)) })
        return [convert(theme, fileName: fileName)]
    }

    /// Every color theme a `.vsix` contributes, per its `package.json`.
    public static func themes(fromExtension data: Data, fileName: String) throws -> [Theme] {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(data: data)
        } catch {
            throw ThemeImportError.unreadable(fileName)
        }
        guard let manifestData = try archive.contents(of: "extension/package.json"),
            let manifest = try LenientJSON.parse(manifestData) as? [String: Any]
        else { throw ThemeImportError.noThemesInExtension }
        let contributes = manifest["contributes"] as? [String: Any]
        let entries = contributes?["themes"] as? [[String: Any]] ?? []
        var themes: [Theme] = []
        for entry in entries {
            guard let path = entry["path"] as? String else { continue }
            let themePath = normalize("extension/" + path)
            guard let themeData = try archive.contents(of: themePath) else { continue }
            let folder = (themePath as NSString).deletingLastPathComponent
            let label = entry["label"] as? String ?? (path as NSString).lastPathComponent
            let theme = try VSCodeTheme(
                data: themeData, fallbackName: label,
                load: { try? archive.contents(of: normalize((folder as NSString).appendingPathComponent($0))) })
            let uiTheme = (entry["uiTheme"] as? String)?.lowercased()
            let hint = uiTheme.map { $0 == "vs-dark" || $0 == "hc-black" }
            var converted = convert(theme, fileName: fileName, darkHint: hint)
            // The extension's label is the name people know it by.
            if let label = entry["label"] as? String { converted.name = label }
            themes.append(converted)
        }
        guard !themes.isEmpty else { throw ThemeImportError.noThemesInExtension }
        return themes
    }

    /// Resolves `.` and `..` in a slash-separated path inside an archive.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." || part.isEmpty { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
            } else {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    // MARK: - Mapping

    /// A theme from VS Code settings. Workbench colors fill the brand roles, token colors
    /// fill markdown and code styles, and anything missing comes from Mocha or Latte.
    public static func convert(_ source: VSCodeTheme, fileName: String, darkHint: Bool? = nil) -> Theme {
        let isDark = source.isDark(hint: darkHint)
        let base = Theme.default(dark: isDark)
        let page =
            color(source.colors["editor.background"]) ?? color(source.rules.defaultBackground) ?? base.palette.page
        let lookup = Lookup(source: source, page: page)
        let palette = self.palette(lookup, base: base.palette, isDark: isDark)
        let (preview, raw) = markdownStyles(lookup, palette: palette)
        var code = CodeToken.styles(palette)
        for (token, stacks) in codeScopes {
            let found = lookup.code(stacks)
            guard found != TokenStyle() else { continue }
            code[token] = (code[token] ?? TokenStyle()).merged(with: found)
        }
        let slug = source.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return Theme(
            id: "imported-" + String(slug) + "-" + String(UUID().uuidString.prefix(8)).lowercased(),
            name: source.name, isDark: isDark, origin: .imported(fileName: fileName), palette: palette,
            editor: editorColors(lookup, palette: palette), preview: preview, raw: raw, code: code)
    }

    /// The brand roles: workbench colors where VS Code has a match, the token colors that
    /// play the same part in Catppuccin (keywords are mauve, numbers peach), else the base.
    private static func palette(_ lookup: Lookup, base: BrandPalette, isDark: Bool) -> BrandPalette {
        let page = lookup.page
        let ink =
            lookup.ui("editor.foreground") ?? color(lookup.source.rules.defaultForeground, over: page)
            ?? lookup.ui("foreground") ?? base.ink
        let black = PaletteColor(hex: 0x000000)
        var palette = base
        palette.name = lookup.source.name
        palette.isDark = isDark
        palette.page = page
        palette.ink = ink
        palette.sidebar = lookup.ui("sideBar.background") ?? page.mixed(with: black, amount: isDark ? 0.2 : 0.035)
        palette.crust =
            lookup.ui("titleBar.activeBackground", "activityBar.background")
            ?? page.mixed(with: black, amount: isDark ? 0.4 : 0.08)
        palette.surface0 = page.mixed(with: ink, amount: 0.12)
        palette.surface1 = page.mixed(with: ink, amount: 0.2)
        palette.overlay0 = lookup.ui("editorLineNumber.foreground") ?? page.mixed(with: ink, amount: 0.4)
        palette.overlay1 = lookup.code(["comment.line"]).color ?? page.mixed(with: ink, amount: 0.5)
        palette.subtext = lookup.ui("descriptionForeground") ?? page.mixed(with: ink, amount: 0.75)
        palette.magic =
            lookup.code(["keyword.control"], ["storage.type"]).color ?? lookup.ui("focusBorder") ?? base.magic
        palette.caret = lookup.code(["constant.numeric"]).color ?? lookup.ui("editorCursor.foreground") ?? base.caret
        palette.callout =
            lookup.code(["entity.name.type.class"], ["support.type"]).color ?? lookup.ui("editorWarning.foreground")
            ?? base.callout
        palette.sparkle = lookup.code(["constant.character.escape"], ["string.regexp"]).color ?? base.sparkle
        palette.lavender =
            lookup.code(["variable.other.property"], ["support.type.property-name"], ["variable.parameter"]).color
            ?? base.lavender
        palette.link = lookup.ui("textLink.foreground") ?? lookup.code(["entity.name.function"]).color ?? base.link
        palette.string = lookup.code(["string.quoted.double"]).color ?? base.string
        palette.quote = lookup.code(["markup.quote"]).color ?? lookup.code(["keyword.operator"]).color ?? base.quote
        palette.error =
            lookup.ui("errorForeground", "editorError.foreground") ?? lookup.code(["invalid.illegal"]).color
            ?? base.error
        return palette
    }

    private static func editorColors(_ lookup: Lookup, palette: BrandPalette) -> EditorColors {
        var editor = EditorColors(palette: palette)
        // Some high-contrast themes select in a color as bright as the text; keep it readable.
        if let selection = lookup.ui("editor.selectionBackground"),
            abs(selection.luminance - palette.ink.luminance) > 0.1
        {
            editor.selection = selection
        }
        editor.caret = lookup.ui("editorCursor.foreground") ?? palette.caret
        editor.lineHighlight = lookup.ui("editor.lineHighlightBackground") ?? editor.lineHighlight
        editor.gutter = lookup.ui("editorLineNumber.foreground") ?? editor.gutter
        editor.border = lookup.ui("editorGroup.border", "panel.border") ?? editor.border
        return editor
    }

    /// Raw takes the theme's markdown token colors as they are. Preview keeps its prose look
    /// but takes the colors for the parts people recognize a theme by.
    private static func markdownStyles(_ lookup: Lookup, palette: BrandPalette) -> (
        preview: [MarkdownToken: TokenStyle], raw: [MarkdownToken: TokenStyle]
    ) {
        var raw = MarkdownToken.rawStyles(palette)
        var preview = MarkdownToken.previewStyles(palette)
        for (token, stacks) in markdownScopes {
            guard let found = lookup.markdown(stacks) else { continue }
            raw[token] = (raw[token] ?? TokenStyle()).merged(with: found)
            if previewTakesColor.contains(token), let color = found.color {
                preview[token] = (preview[token] ?? TokenStyle()).merged(with: TokenStyle(color: color))
            }
        }
        if let codeBackground = lookup.ui("textCodeBlock.background") {
            preview[.codeBlock]?.background = codeBackground
            preview[.inlineCode]?.background = codeBackground
        }
        return (preview, raw)
    }

    static func color(_ string: String?, over background: PaletteColor? = nil) -> PaletteColor? {
        string.flatMap { PaletteColor(hex: $0, over: background) }
    }

    /// Reads colors out of a VS Code theme against its editor background.
    private struct Lookup {
        let source: VSCodeTheme
        let page: PaletteColor

        /// The first of `keys` the theme sets in `colors`.
        func ui(_ keys: String...) -> PaletteColor? {
            for key in keys {
                if let color = ThemeImport.color(source.colors[key], over: page) { return color }
            }
            return nil
        }

        /// The style for the first scope stack any rule matches, inside a generic source file.
        func code(_ stacks: [String]...) -> TokenStyle {
            code(stacks)
        }

        func code(_ stacks: [[String]]) -> TokenStyle {
            for stack in stacks {
                if let style = style(["source"] + stack) { return style }
            }
            return TokenStyle()
        }

        func markdown(_ stacks: [[String]]) -> TokenStyle? {
            for stack in stacks {
                if let style = style(stack) { return style }
            }
            return nil
        }

        private func style(_ stack: [String]) -> TokenStyle? {
            guard let match = source.rules.match(stack) else { return nil }
            var style = TokenStyle(
                color: ThemeImport.color(match.foreground, over: page),
                background: ThemeImport.color(match.background, over: page))
            if let fontStyle = match.fontStyle?.lowercased() {
                let words = Set(fontStyle.split(separator: " "))
                style.bold = words.contains("bold")
                style.italic = words.contains("italic")
                style.underline = words.contains("underline")
                style.strikethrough = words.contains("strikethrough")
            }
            return style
        }
    }
}

/// Which TextMate scopes stand for which tokens.
extension ThemeImport {
    static let previewTakesColor: Set<MarkdownToken> = [
        .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .bold, .italic, .link, .quote,
        .listMarker, .inlineCode,
    ]

    /// The TextMate scopes VS Code's markdown grammar gives each token, outermost first.
    /// Some tokens list more than one stack to try.
    static let markdownScopes: [(MarkdownToken, [[String]])] = {
        let markdown = "text.html.markdown"
        var scopes: [(MarkdownToken, [[String]])] = []
        for level in 1...6 {
            scopes.append(
                (
                    .heading(level),
                    [
                        [
                            markdown, "markup.heading.markdown", "heading.\(level).markdown",
                            "entity.name.section.markdown",
                        ]
                    ]
                ))
        }
        scopes += [
            (.bold, [[markdown, "markup.bold.markdown"]]),
            (.italic, [[markdown, "markup.italic.markdown"]]),
            (.strikethrough, [[markdown, "markup.strikethrough.markdown"]]),
            (.inlineCode, [[markdown, "markup.inline.raw.string.markdown"]]),
            (.codeFence, [[markdown, "markup.fenced_code.block.markdown", "punctuation.definition.markdown"]]),
            (.link, [[markdown, "meta.link.inline.markdown", "string.other.link.title.markdown"]]),
            (.linkDestination, [[markdown, "meta.link.inline.markdown", "markup.underline.link.markdown"]]),
            (.quote, [[markdown, "markup.quote.markdown", "punctuation.definition.quote.begin.markdown"]]),
            (
                .listMarker,
                [[markdown, "markup.list.unnumbered.markdown", "punctuation.definition.list.begin.markdown"]]
            ),
            (.emphasisMarker, [[markdown, "markup.bold.markdown", "punctuation.definition.bold.markdown"]]),
            (
                .syntaxMarker,
                [[markdown, "meta.link.inline.markdown", "punctuation.definition.link.title.begin.markdown"]]
            ),
            (
                .frontmatter,
                [[markdown, "meta.embedded.block.frontmatter", "punctuation.definition.tag.begin.markdown"]]
            ),
            (.frontmatterKey, [[markdown, "meta.embedded.block.frontmatter", "source.yaml", "entity.name.tag.yaml"]]),
            (
                .frontmatterValue,
                [[markdown, "meta.embedded.block.frontmatter", "source.yaml", "string.unquoted.plain.out.yaml"]]
            ),
            (
                .html,
                [[markdown, "text.html.basic", "meta.tag.structure.any.html", "entity.name.tag.structure.any.html"]]
            ),
            (.mdx, [["source.mdx", "meta.tag.jsx", "entity.name.tag.jsx"]]),
            (.mdxAttribute, [["source.mdx", "meta.tag.jsx", "entity.other.attribute-name.jsx"]]),
            (.mdxString, [["source.mdx", "meta.tag.jsx", "string.quoted.double.jsx"]]),
        ]
        return scopes
    }()

    /// The scopes language grammars give each code token, most typical first.
    static let codeScopes: [(CodeToken, [[String]])] = [
        (.keyword, [["keyword.control"], ["storage.type"], ["keyword"]]),
        (.string, [["string.quoted.double"], ["string"]]),
        (.comment, [["comment.line.double-slash"], ["comment"]]),
        (.function, [["entity.name.function"], ["support.function"]]),
        (.type, [["entity.name.type.class"], ["entity.name.type"], ["support.type"]]),
        (.number, [["constant.numeric"]]),
        (.constant, [["constant.language"], ["constant"]]),
        (.variable, [["variable.other.readwrite"], ["variable"]]),
        (.property, [["variable.other.property"], ["support.type.property-name"], ["variable.other.object.property"]]),
        (.operator, [["keyword.operator"]]),
        (.punctuation, [["punctuation.separator"], ["punctuation"]]),
        (.tag, [["entity.name.tag"]]),
        (.attribute, [["entity.other.attribute-name"]]),
        (.escape, [["constant.character.escape"]]),
        (.builtin, [["support.function.builtin"], ["variable.language"]]),
    ]
}
