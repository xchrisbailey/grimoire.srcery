import Markdown

extension MarkdownParser {
    /// Whether changing prose left the parsed Markdown structure and non-prose payloads
    /// intact. Source markers alone cannot guarantee this: delimiter flanking and quoted
    /// link titles depend on their surrounding text.
    public static func hasSameStructure(_ source: String, as candidate: String) -> Bool {
        sameStructure(
            Markdown.Document(parsing: source, options: []), Markdown.Document(parsing: candidate, options: []))
    }

    private static func sameStructure(_ source: any Markup, _ candidate: any Markup) -> Bool {
        guard ObjectIdentifier(type(of: source)) == ObjectIdentifier(type(of: candidate)),
            inlineAttributes(source) == inlineAttributes(candidate)
        else { return false }
        // Text tokenization may change with escapes or translated punctuation. Its values
        // and token counts are prose, while its structural parents and siblings must survive.
        let original = source.children.filter { !($0 is Text) }
        let projected = candidate.children.filter { !($0 is Text) }
        return original.count == projected.count && zip(original, projected).allSatisfy { sameStructure($0, $1) }
    }

    private static func inlineAttributes(_ node: any Markup) -> [String?] {
        switch node {
        case let link as Link: [link.destination, link.title]
        case let image as Image: [image.source, image.title]
        case let code as InlineCode: [code.code]
        case let html as InlineHTML: [html.rawHTML]
        case let symbol as SymbolLink: [symbol.destination]
        case let custom as CustomInline: [custom.text]
        default: blockAttributes(node)
        }
    }

    private static func blockAttributes(_ node: any Markup) -> [String?] {
        switch node {
        case let code as CodeBlock: [code.language, code.code]
        case let heading as Heading: [String(heading.level)]
        case let list as OrderedList: [String(list.startIndex)]
        case let item as Markdown.ListItem: [item.checkbox.map { String(describing: $0) }]
        case let table as Table: table.columnAlignments.map { $0.map { String(describing: $0) } }
        case let html as HTMLBlock: [html.rawHTML]
        default: []
        }
    }
}
