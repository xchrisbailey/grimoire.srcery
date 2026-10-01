import Foundation
import GrimoireCore
import UniformTypeIdentifiers

/// How an exported page looks.
public enum ExportStyle: Sendable {
    /// The theme's own colors, for HTML read on screen.
    case theme(Theme)
    /// Dark text on white with Catppuccin Latte accents, for paper and PDF.
    case print
}

/// Turns a markdown file into one self-contained HTML page: images inlined, code
/// highlighted, Geist embedded, styled from a theme or for print.
public enum DocumentExport {
    public static func html(
        markdown: String, fileURL: URL?, title: String, style: ExportStyle, embedFonts: Bool = true,
        paged: Bool = false
    ) -> String {
        let theme = style.theme
        let folder = fileURL?.deletingLastPathComponent()
        var renderer = HTMLRenderer()
        renderer.highlightCode = { code, language in
            guard let language, CodeHighlighter.supports(language) else { return nil }
            return highlightedHTML(
                code, highlights: CodeHighlighter.shared.highlightSync(code, language: language), theme: theme)
        }
        renderer.imageSource = { source in dataURI(for: source, relativeTo: folder) ?? source }
        let flavor = fileURL.flatMap { DocumentFlavor(pathExtension: $0.pathExtension) } ?? .markdown
        let body = renderer.render(markdown, flavor: flavor)
        return """
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="generator" content="Grimoire">
            <title>\(HTMLRenderer.escape(title))</title>
            <style>
            \(embedFonts ? fontFaces() : "")\(stylesheet(theme))
            </style>
            </head>
            <body\(paged ? " class=\"paged\"" : "")>
            <main>
            \(body)</main>
            </body>
            </html>

            """
    }

    // MARK: - Code

    /// Escaped code with each highlighted run in a colored span.
    static func highlightedHTML(_ code: String, highlights: [CodeHighlight], theme: Theme) -> String {
        let text = code as NSString
        // Paint per UTF-16 unit, later (inner) runs over earlier ones, then group runs.
        var tokens = [CodeToken?](repeating: nil, count: text.length)
        for highlight in highlights where NSMaxRange(highlight.range) <= text.length {
            for offset in highlight.range.location..<NSMaxRange(highlight.range) { tokens[offset] = highlight.token }
        }
        var html = ""
        var start = 0
        while start < text.length {
            var end = start + 1
            while end < text.length, tokens[end] == tokens[start] { end += 1 }
            let piece = HTMLRenderer.escape(text.substring(with: NSRange(location: start, length: end - start)))
            if let token = tokens[start] {
                html += "<span style=\"\(css(theme.style(token)))\">\(piece)</span>"
            } else {
                html += piece
            }
            start = end
        }
        return html
    }

    private static func css(_ style: TokenStyle) -> String {
        var rules: [String] = []
        if let color = style.color { rules.append("color: \(color)") }
        if style.bold == true { rules.append("font-weight: 700") }
        if style.italic == true { rules.append("font-style: italic") }
        if style.underline == true { rules.append("text-decoration: underline") }
        return rules.joined(separator: "; ")
    }

    // MARK: - Images

    /// A data URI for a local image, so the page carries it. Web images stay links.
    public static func dataURI(for source: String, relativeTo folder: URL?) -> String? {
        if let url = URL(string: source), let scheme = url.scheme, scheme != "file" { return nil }
        let path = source.removingPercentEncoding ?? source
        let file: URL
        if let url = URL(string: source), url.isFileURL {
            file = url
        } else if path.hasPrefix("/") {
            file = URL(filePath: path)
        } else if let folder {
            file = folder.appending(path: path).standardizedFileURL
        } else {
            return nil
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    // MARK: - Style

    private static func fontFaces() -> String {
        var css = ""
        for url in BrandFont.registeredFontURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            let name = url.lastPathComponent
            let family = name.hasPrefix("GeistMono") ? "Geist Mono" : "Geist"
            let italic = name.contains("Italic")
            css += """
                @font-face { font-family: "\(family)"; font-style: \(italic ? "italic" : "normal"); \
                font-weight: 100 900; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format("truetype"); }

                """
        }
        return css
    }

    static func stylesheet(_ theme: Theme) -> String {
        baseStyles(theme) + blockStyles(theme) + pagedStyles
    }

    private static func baseStyles(_ theme: Theme) -> String {
        let palette = theme.palette
        let heading = theme.style(.heading1, raw: false).color ?? palette.ink
        let link = theme.style(.link, raw: false).color ?? palette.link
        let codeBackground = theme.style(.codeBlock, raw: false).background ?? palette.surface0
        return """
            :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
            html { background: \(palette.page); }
            body { margin: 0; color: \(palette.ink); background: \(palette.page);
              font: 15.5px/1.7 "Geist", -apple-system, system-ui, sans-serif;
              -webkit-font-smoothing: antialiased; }
            main { max-width: 680px; margin: 0 auto; padding: 48px 24px 64px; }
            h1, h2, h3, h4, h5, h6 { color: \(heading); line-height: 1.2; margin: 1.6em 0 0.5em;
              break-after: avoid; }
            h1 { font-size: 34px; font-weight: 700; letter-spacing: -0.025em; margin-top: 0.4em; }
            h2 { font-size: 20px; font-weight: 650; }
            h3 { font-size: 17px; font-weight: 650; }
            h4, h5, h6 { font-size: 15.5px; font-weight: 650; }
            p, ul, ol, table, pre, blockquote { margin: 0 0 1em; }
            a { color: \(link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            strong { font-weight: 700; }
            del { color: \(palette.subtext); }
            code, pre { font-family: "Geist Mono", ui-monospace, Menlo, monospace; }
            code { font-size: 0.9em; background: \(codeBackground); border-radius: 4px; padding: 0.1em 0.3em; }
            pre { background: \(codeBackground); border-radius: 8px; padding: 12px 14px; overflow-x: auto;
              font-size: 13.5px; line-height: 1.5; break-inside: avoid; }
            pre code { background: none; padding: 0; font-size: inherit; }
            hr { border: none; border-top: 1px solid \(palette.surface1); margin: 2em 0; }
            img { max-width: 100%; border-radius: 8px; break-inside: avoid; }

            """
    }

    /// Quotes, callouts, task lists and tables.
    private static func blockStyles(_ theme: Theme) -> String {
        let palette = theme.palette
        let quote = theme.style(.quote, raw: false).color ?? palette.subtext
        let codeBackground = theme.style(.codeBlock, raw: false).background ?? palette.surface0
        let marker = theme.style(.listMarker, raw: false).color ?? palette.caret
        var css = """
            blockquote { color: \(quote); border-left: 3px solid \(palette.magic); margin-left: 0;
              padding: 0 0 0 14px; }
            blockquote.callout { border-left-color: \(palette.callout); border-radius: 0 8px 8px 0;
              background: \(palette.page.mixed(with: palette.callout, amount: 0.1));
              padding: 10px 14px; color: \(palette.ink); }
            .callout-title { font-weight: 650; margin-bottom: 0.3em; color: \(palette.callout); }

            """
        let callouts: [(String, PaletteColor)] = [
            ("note", palette.link), ("tip", palette.string), ("important", palette.magic), ("caution", palette.error),
        ]
        for (kind, color) in callouts {
            css +=
                "blockquote.callout-\(kind) { border-left-color: \(color); }\n"
                + ".callout-\(kind) .callout-title { color: \(color); }\n"
        }
        css += """
            ul.tasks { list-style: none; padding-left: 0.4em; }
            ul.tasks > li:not(.task) { list-style: disc; margin-left: 1.2em; }
            li.task input { appearance: none; -webkit-appearance: none; width: 0.85em; height: 0.85em;
              margin: 0 0.55em 0 0; vertical-align: -0.1em; border: 1.5px solid \(palette.overlay0);
              border-radius: 0.25em; }
            li.task input:checked { border-color: \(palette.magic);
              background: \(palette.magic) url("data:image/svg+xml;utf8,\(checkmark(palette.page))")
              center / 80% no-repeat; }
            li.task.done { color: \(palette.overlay1); text-decoration: line-through;
              text-decoration-color: \(palette.overlay0); }
            li > p { margin: 0; }
            ::marker { color: \(marker); }
            table { border-collapse: collapse; width: auto; break-inside: avoid; }
            th, td { border: 1px solid \(palette.surface1); padding: 6px 12px; text-align: left;
              vertical-align: top; }
            th { background: \(codeBackground); font-weight: 650; }
            @media print { main { max-width: none; padding: 0; } html, body { background: \(palette.page); } }

            """
        return css
    }

    /// Sizes for paper: the PDF and print layout.
    private static let pagedStyles = """
        .paged main { max-width: none; padding: 0; }
        body.paged { font-size: 11.5px; line-height: 1.6; }
        .paged h1 { font-size: 26px; } .paged h2 { font-size: 16px; } .paged h3 { font-size: 13.5px; }
        .paged h4, .paged h5, .paged h6 { font-size: 11.5px; } .paged pre { font-size: 9.5px; }
        @page { margin: 0.75in; }

        """
}

extension DocumentExport {
    /// A white tick for checked task boxes, as an SVG data URI body.
    fileprivate static func checkmark(_ color: PaletteColor) -> String {
        let hex = color.description.replacingOccurrences(of: "#", with: "%23")
        return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'><path d='M2.5 6.2l2.4 2.4 4.6-5' "
            + "fill='none' stroke='\(hex)' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'/></svg>"
    }
}

extension ExportStyle {
    /// The theme a page is drawn with: print uses Latte on white.
    var theme: Theme {
        switch self {
        case .theme(let theme): return theme
        case .print:
            var theme = Theme.latte
            theme.palette.page = PaletteColor(hex: 0xFFFFFF)
            theme.palette.ink = PaletteColor(hex: 0x24273A)
            theme.preview[.codeBlock]?.background = PaletteColor(hex: 0xF3F4F7)
            theme.preview[.inlineCode]?.background = PaletteColor(hex: 0xF3F4F7)
            return theme
        }
    }
}
