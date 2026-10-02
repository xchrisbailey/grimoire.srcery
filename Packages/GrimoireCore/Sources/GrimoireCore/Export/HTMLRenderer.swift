import Foundation
import Markdown

/// Renders a markdown file as an HTML body: frontmatter and MDX statements left out, text
/// escaped, headings given ids, task lists as checkboxes and GitHub alerts as callouts.
public struct HTMLRenderer {
    /// HTML for a code block's contents (already escaped), or nil for plain escaped code.
    public var highlightCode: ((_ code: String, _ language: String?) -> String?)?
    /// The `src` to use for an image, such as a data URI for a self-contained page.
    public var imageSource: ((_ source: String) -> String)?
    /// Whether a single line break inside a paragraph becomes `<br>`, rather than joining
    /// the lines as strict markdown does.
    public var keepsLineBreaks = false

    public init() {}

    public func render(_ text: String, flavor: DocumentFlavor = .markdown) -> String {
        let document = Document(parsing: text, flavor: flavor)
        // Keep the blocks a reader sees: no frontmatter, no MDX imports or JSX.
        var body = ""
        for block in document.blocks where block.kind != .mdx {
            body += block.source + block.trailing
        }
        var walker = Walker(renderer: self)
        walker.visit(Markdown.Document(parsing: body))
        return walker.result
    }

    /// GitHub's heading anchors: lowercased, punctuation dropped, spaces as hyphens.
    public static func slug(_ heading: String) -> String {
        heading.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            .replacingOccurrences(of: " ", with: "-")
    }

    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    private struct Walker: MarkupWalker {
        let renderer: HTMLRenderer
        var result = ""
        var usedSlugs: [String: Int] = [:]
        var inTableHead = false
        var columnAlignments: [Table.ColumnAlignment?] = []
        var column = 0

        init(renderer: HTMLRenderer) {
            self.renderer = renderer
        }

        mutating func visitHeading(_ heading: Heading) {
            var slug = HTMLRenderer.slug(heading.plainText)
            if let count = usedSlugs[slug] {
                usedSlugs[slug] = count + 1
                slug += "-\(count)"
            } else {
                usedSlugs[slug] = 1
            }
            result += "<h\(heading.level) id=\"\(HTMLRenderer.escape(slug))\">"
            descendInto(heading)
            result += "</h\(heading.level)>\n"
        }

        mutating func visitParagraph(_ paragraph: Paragraph) {
            // A list item holding just one paragraph reads as a tight item.
            let inTightList = paragraph.parent is Markdown.ListItem && paragraph.parent?.childCount == 1
            if !inTightList { result += "<p>" }
            descendInto(paragraph)
            result += inTightList ? "" : "</p>\n"
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            // `> [!NOTE]` and friends become callouts, as on GitHub.
            if let first = blockQuote.child(at: 0) as? Paragraph, let text = first.child(at: 0) as? Text,
                let match = text.string.firstMatch(of: /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/)
            {
                let kind = match.1.lowercased()
                result += "<blockquote class=\"callout callout-\(kind)\"><p class=\"callout-title\">"
                result += HTMLRenderer.escape(kind.capitalized) + "</p>\n"
                var rest = text.string.dropFirst(match.0.count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { rest = HTMLRenderer.escape(rest) }
                result += "<p>" + rest
                var remaining = Array(first.children.dropFirst())
                // The line break after `[!NOTE]` starts the callout's text, not a new line.
                if rest.isEmpty, remaining.first is SoftBreak || remaining.first is LineBreak {
                    remaining.removeFirst()
                }
                for child in remaining { visit(child) }
                result += "</p>\n"
                for child in blockQuote.children.dropFirst() { visit(child) }
                result += "</blockquote>\n"
                return
            }
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            let language = codeBlock.language.flatMap { $0.split(separator: " ").first.map(String.init) }
            let attribute = language.map { " class=\"language-\(HTMLRenderer.escape($0))\"" } ?? ""
            var code = codeBlock.code
            if code.hasSuffix("\n") { code.removeLast() }
            let body = renderer.highlightCode?(code, language) ?? HTMLRenderer.escape(code)
            result += "<pre><code\(attribute)>\(body)</code></pre>\n"
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
            result += "<hr />\n"
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) {
            result += html.rawHTML
        }

        mutating func visitOrderedList(_ orderedList: OrderedList) {
            let start = orderedList.startIndex != 1 ? " start=\"\(orderedList.startIndex)\"" : ""
            result += "<ol\(start)>\n"
            descendInto(orderedList)
            result += "</ol>\n"
        }

        mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
            let isTasks = unorderedList.children.contains { ($0 as? Markdown.ListItem)?.checkbox != nil }
            result += isTasks ? "<ul class=\"tasks\">\n" : "<ul>\n"
            descendInto(unorderedList)
            result += "</ul>\n"
        }

        mutating func visitListItem(_ listItem: Markdown.ListItem) {
            switch listItem.checkbox {
            case .checked: result += "<li class=\"task done\"><input type=\"checkbox\" disabled checked /> "
            case .unchecked: result += "<li class=\"task\"><input type=\"checkbox\" disabled /> "
            case nil: result += "<li>"
            }
            descendInto(listItem)
            result += "</li>\n"
        }

        mutating func visitTable(_ table: Table) {
            columnAlignments = table.columnAlignments
            result += "<table>\n"
            descendInto(table)
            result += "</table>\n"
        }

        mutating func visitTableHead(_ tableHead: Table.Head) {
            inTableHead = true
            column = 0
            result += "<thead>\n<tr>\n"
            descendInto(tableHead)
            result += "</tr>\n</thead>\n<tbody>\n"
            inTableHead = false
        }

        mutating func visitTableBody(_ tableBody: Table.Body) {
            descendInto(tableBody)
            result += "</tbody>\n"
        }

        mutating func visitTableRow(_ tableRow: Table.Row) {
            column = 0
            result += "<tr>\n"
            descendInto(tableRow)
            result += "</tr>\n"
        }

        mutating func visitTableCell(_ tableCell: Table.Cell) {
            let tag = inTableHead ? "th" : "td"
            var alignment = ""
            if column < columnAlignments.count, let align = columnAlignments[column] {
                alignment = " style=\"text-align: \(align == .left ? "left" : align == .center ? "center" : "right")\""
            }
            column += 1
            result += "<\(tag)\(alignment)>"
            descendInto(tableCell)
            result += "</\(tag)>\n"
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            result += "<code>\(HTMLRenderer.escape(inlineCode.code))</code>"
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            wrap("em", emphasis)
        }

        mutating func visitStrong(_ strong: Strong) {
            wrap("strong", strong)
        }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
            wrap("del", strikethrough)
        }

        mutating func visitImage(_ image: Image) {
            let source = image.source.map { renderer.imageSource?($0) ?? $0 } ?? ""
            result += "<img src=\"\(HTMLRenderer.escape(source))\" alt=\"\(HTMLRenderer.escape(image.plainText))\""
            if let title = image.title, !title.isEmpty { result += " title=\"\(HTMLRenderer.escape(title))\"" }
            result += " />"
        }

        mutating func visitLink(_ link: Link) {
            result += "<a href=\"\(HTMLRenderer.escape(link.destination ?? ""))\">"
            descendInto(link)
            result += "</a>"
        }

        mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
            result += inlineHTML.rawHTML
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) {
            result += "<br />\n"
        }

        mutating func visitSoftBreak(_ softBreak: SoftBreak) {
            result += renderer.keepsLineBreaks ? "<br />\n" : "\n"
        }

        mutating func visitText(_ text: Text) {
            result += HTMLRenderer.escape(text.string)
        }

        private mutating func wrap(_ tag: String, _ markup: Markup) {
            result += "<\(tag)>"
            descendInto(markup)
            result += "</\(tag)>"
        }
    }
}
