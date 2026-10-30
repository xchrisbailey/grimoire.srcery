import Foundation
import Markdown

extension MarkdownParser {
    /// Whether changing prose left the parsed Markdown structure and non-prose payloads
    /// intact. Source markers alone cannot guarantee this: delimiter flanking and quoted
    /// link titles depend on their surrounding text.
    /// `edits` are ordered, nonoverlapping UTF-16 prose replacements in `source`.
    public static func hasSameStructure(_ source: String, as candidate: String, replacing edits: [TextEdit]) -> Bool {
        guard let projection = StructuralProjection(source: source, candidate: candidate, edits: edits) else {
            return false
        }
        if source.utf8.elementsEqual(candidate.utf8) { return true }
        return sameStructure(
            Markdown.Document(parsing: source, options: []), Markdown.Document(parsing: candidate, options: []),
            projection: projection)
    }

    private static func sameStructure(
        _ source: any Markup, _ candidate: any Markup, projection: StructuralProjection
    ) -> Bool {
        guard ObjectIdentifier(type(of: source)) == ObjectIdentifier(type(of: candidate)),
            inlineAttributes(source) == inlineAttributes(candidate), projection.preservesRange(source, candidate)
        else { return false }
        // Text tokenization may change with escapes or translated punctuation. Its values
        // and token counts are prose, while its structural parents and siblings must survive.
        let original = source.children.filter { !($0 is Text) }
        let projected = candidate.children.filter { !($0 is Text) }
        return original.count == projected.count
            && zip(original, projected).allSatisfy { sameStructure($0, $1, projection: projection) }
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

private struct StructuralProjection {
    let source: StructuralLocations
    let candidate: StructuralLocations
    let edits: [TextEdit]

    init?(source: String, candidate: String, edits: [TextEdit]) {
        var end = 0
        for edit in edits {
            guard edit.range.lowerBound >= end, edit.range.upperBound <= source.utf16.count,
                !edit.range.isEmpty, !edit.replacement.isEmpty, Range(NSRange(edit.range), in: source) != nil
            else { return nil }
            end = edit.range.upperBound
        }
        let projected = edits.reversed().reduce(source) { editSource, edit in edit.applied(to: editSource) }
        guard projected.utf8.elementsEqual(candidate.utf8) else { return nil }
        self.source = StructuralLocations(source)
        self.candidate = StructuralLocations(candidate)
        self.edits = edits
    }

    func preservesRange(_ original: any Markup, _ projected: any Markup) -> Bool {
        // The document is anchored by the verified complete source-to-candidate edit map.
        if original is Markdown.Document { return true }
        guard let originalRange = source.range(of: original), let projectedRange = candidate.range(of: projected)
        else { return false }
        if original is any InlineMarkup {
            guard !originalRange.isEmpty,
                edits.allSatisfy({
                    !$0.range.contains(originalRange.lowerBound) && !$0.range.contains(originalRange.upperBound - 1)
                })
            else { return false }
        }
        if original is SoftBreak || original is LineBreak {
            guard edits.allSatisfy({ !$0.range.overlaps(originalRange) }) else { return false }
        }
        return originalOffset(projectedRange.lowerBound) == originalRange.lowerBound
            && originalOffset(projectedRange.upperBound) == originalRange.upperBound
    }

    private func originalOffset(_ offset: Int) -> Int? {
        var delta = 0
        for edit in edits {
            let start = edit.range.lowerBound + delta
            let end = start + edit.replacement.utf16.count
            if offset < start { return offset - delta }
            if offset == start { return edit.range.lowerBound }
            // Boundaries inside generated prose have no unique source owner. In particular,
            // never assign a newly active delimiter to an arbitrary old delimiter.
            if offset < end { return nil }
            if offset == end { return edit.range.upperBound }
            delta += edit.replacement.utf16.count - edit.range.count
        }
        return offset - delta
    }
}

private struct StructuralLocations {
    let text: String
    let lines: Lines

    init(_ text: String) {
        self.text = text
        lines = Lines(Array(text.utf8))
    }

    func range(of node: any Markup) -> Range<Int>? {
        guard let range = parsedRange(of: node), let lower = offset(range.lowerBound),
            let upper = offset(range.upperBound),
            lower <= upper
        else { return nil }
        return lower..<upper
    }

    private func parsedRange(of node: any Markup) -> SourceRange? {
        if let range = node.range { return range }
        // cmark omits break ranges. Its immediate parsed neighbors can still identify
        // one immutable gap; missing neighbors or overlapping ranges leave ownership unknown.
        guard node is SoftBreak || node is LineBreak, let parent = node.parent, node.indexInParent > 0,
            node.indexInParent + 1 < parent.childCount,
            let previous = parent.child(at: node.indexInParent - 1)?.range,
            let next = parent.child(at: node.indexInParent + 1)?.range, previous.upperBound < next.lowerBound
        else { return nil }
        return previous.upperBound..<next.lowerBound
    }

    private func offset(_ location: SourceLocation) -> Int? {
        guard location.line > 0, location.line <= lines.count, location.column > 0 else { return nil }
        let byte = lines.starts[location.line - 1] + location.column - 1
        guard byte <= lines.contentEnd(ofLine: location.line - 1),
            let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: byte, limitedBy: text.utf8.endIndex),
            let index = String.Index(utf8Index, within: text), let utf16Index = index.samePosition(in: text.utf16)
        else { return nil }
        return text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
    }
}
