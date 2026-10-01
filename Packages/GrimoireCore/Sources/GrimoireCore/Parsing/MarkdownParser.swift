import Markdown

/// Splits markdown into blocks without losing a byte.
///
/// swift-markdown (cmark-gfm) finds where each block starts. The text from one start
/// to the next becomes a block's `source` plus `trailing`, so the blocks always cover
/// the whole input and `parse(x).markdown == x` holds by construction.
public enum MarkdownParser {
    public static func parse(_ text: String, flavor: DocumentFlavor = .markdown) -> Document {
        parse(text, flavor: flavor, detectFrontmatter: true)
    }

    static func parse(_ text: String, flavor: DocumentFlavor, detectFrontmatter: Bool) -> Document {
        let bytes = Array(text.utf8)
        let lines = Lines(bytes)

        var bodyStart = 0
        var frontmatterEnd: Int?
        if detectFrontmatter, let end = lines.frontmatterEnd() {
            frontmatterEnd = end
            bodyStart = end
        }

        var starts: [Start] = []
        let mdxRegions = flavor == .mdx ? MDXScanner(lines: lines).regions(from: bodyStart) : []
        var cursor = bodyStart
        for region in mdxRegions {
            starts += markdownStarts(in: cursor..<region.lowerBound, of: bytes, lines: lines)
            starts.append(Start(offset: region.lowerBound, kind: .mdx))
            cursor = region.upperBound
        }
        starts += markdownStarts(in: cursor..<bytes.count, of: bytes, lines: lines)

        // Blocks start at the beginning of their line. Two starts on the same offset
        // (say, a list whose first item is a nested list) collapse into the first.
        var snapped: [Start] = []
        for var start in starts {
            start.offset = lines.lineStartIfIndented(start.offset)
            if let last = snapped.last, last.offset >= start.offset { continue }
            snapped.append(start)
        }

        var document = Document(flavor: flavor, lineEnding: lines.firstLineEnding() ?? "\n")
        if let frontmatterEnd {
            let firstBlock = snapped.first?.offset ?? bytes.count
            let split = lines.splitTrailing(0..<frontmatterEnd)
            document.frontmatter = Frontmatter(
                source: string(bytes, 0..<split),
                trailing: string(bytes, split..<firstBlock)
            )
        } else {
            document.leading = string(bytes, 0..<(snapped.first?.offset ?? bytes.count))
        }

        for (index, start) in snapped.enumerated() {
            let end = index + 1 < snapped.count ? snapped[index + 1].offset : bytes.count
            let split = lines.splitTrailing(start.offset..<end)
            document.blocks.append(
                Block(
                    kind: start.kind,
                    source: string(bytes, start.offset..<split),
                    trailing: string(bytes, split..<end)
                )
            )
        }
        return document
    }

    struct Start {
        var offset: Int
        var kind: BlockKind
    }

    private static func markdownStarts(in range: Range<Int>, of bytes: [UInt8], lines: Lines) -> [Start] {
        guard !range.isEmpty else { return [] }
        let chunk = string(bytes, range)
        let tree = Markdown.Document(parsing: chunk, options: [])
        let chunkLines = Lines(Array(bytes[range]))
        func offset(_ location: SourceLocation) -> Int {
            range.lowerBound + chunkLines.offset(line: location.line, column: location.column)
        }

        var starts: [Start] = []
        var cursor = range.lowerBound
        for node in tree.children {
            guard let nodeRange = node.range else { continue }
            let nodeStart = offset(nodeRange.lowerBound)
            // cmark drops link reference definitions from the tree. Whatever text sits
            // between two blocks is one of those, so it gets a block of its own.
            // (cmark sometimes reports an end past the next block's start, so clamp.)
            if nodeStart > cursor, let gap = lines.firstNonBlank(in: cursor..<nodeStart) {
                starts.append(Start(offset: gap, kind: .linkDefinitions))
            }
            starts += blockStarts(for: node, at: nodeStart, offset: offset, indent: 0)
            cursor = max(cursor, offset(nodeRange.upperBound))
        }
        if cursor < range.upperBound, let gap = lines.firstNonBlank(in: cursor..<range.upperBound) {
            starts.append(Start(offset: gap, kind: .linkDefinitions))
        }
        return starts
    }

    private static func blockStarts(
        for node: Markup,
        at start: Int,
        offset: (SourceLocation) -> Int,
        indent: Int
    ) -> [Start] {
        switch node {
        case let list as ListItemContainer:
            var starts: [Start] = []
            let firstNumber = (list as? OrderedList).map { Int($0.startIndex) }
            for (index, item) in list.listItems.enumerated() {
                guard let itemRange = item.range else { continue }
                let marker: ListItem.Marker = firstNumber.map { .ordered($0 + index) } ?? .bullet
                let checkbox: ListItem.Checkbox? = item.checkbox.map { $0 == .checked ? .checked : .unchecked }
                let kind = BlockKind.listItem(ListItem(marker: marker, checkbox: checkbox, indent: indent))
                starts.append(Start(offset: offset(itemRange.lowerBound), kind: kind))
                for child in item.children where child is ListItemContainer {
                    guard let childRange = child.range else { continue }
                    starts += blockStarts(
                        for: child, at: offset(childRange.lowerBound), offset: offset, indent: indent + 1)
                }
            }
            return starts
        default:
            return [Start(offset: start, kind: kind(of: node))]
        }
    }

    static func kind(of node: Markup) -> BlockKind {
        switch node {
        case let heading as Heading: .heading(level: heading.level)
        case let paragraph as Paragraph:
            paragraph.childCount == 1 && paragraph.child(at: 0) is Image ? .image : .paragraph
        case is BlockQuote: .blockquote
        case let code as CodeBlock: .codeBlock(language: code.language)
        case is Table: .table
        case is ThematicBreak: .thematicBreak
        case is HTMLBlock: .html
        default: .paragraph
        }
    }

    static func string(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }
}
