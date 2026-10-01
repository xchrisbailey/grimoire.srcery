/// Moves between a block's markdown source and its plain content: strips markers on the
/// way out (`extract`) and writes them on the way back (`render`).
enum BlockText {
    static func extract(from source: String, kind: BlockKind) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        switch kind {
        case .heading: return headingText(lines)
        case .listItem: return listItemText(lines)
        case .blockquote: return lines.map(stripQuoteMarker).joined(separator: "\n")
        case .codeBlock: return codeText(lines)
        case .thematicBreak: return ""
        case .paragraph, .table, .image, .html, .mdx, .linkDefinitions: return source
        }
    }

    private static func headingText(_ lines: [String]) -> String {
        if lines.count > 1, let last = lines.last, isSetextUnderline(last) {
            return lines.dropLast().map { $0.trimmingWhitespace() }.joined(separator: "\n")
        }
        let text = Substring(lines.first ?? "").drop { $0 == " " }.drop { $0 == "#" }.trimmingWhitespace()
        guard text.last == "#" else { return text }
        // An optional closing run of #s counts only after a space.
        guard let beforeHashes = text.lastIndex(where: { $0 != "#" }) else { return "" }
        let separator = text[beforeHashes]
        return separator == " " || separator == "\t" ? text[...beforeHashes].trimmingWhitespace() : text
    }

    private static func listItemText(_ lines: [String]) -> String {
        guard let first = lines.first else { return "" }
        let (prefixWidth, rest) = stripListMarker(first)
        let continuation = lines.dropFirst().map { dropLeadingSpaces($0, upTo: prefixWidth) }
        return ([rest] + continuation).joined(separator: "\n")
    }

    private static func stripQuoteMarker(_ line: String) -> String {
        var text = Substring(dropLeadingSpaces(line, upTo: 3))
        guard text.first == ">" else { return line }
        text = text.dropFirst()
        if text.first == " " { text = text.dropFirst() }
        return String(text)
    }

    private static func codeText(_ lines: [String]) -> String {
        let first = (lines.first ?? "").trimmingWhitespace()
        guard let fenceChar = first.first, first.hasPrefix("```") || first.hasPrefix("~~~") else {
            return lines.map { dropLeadingSpaces($0, upTo: 4) }.joined(separator: "\n")
        }
        let fenceLength = first.prefix { $0 == fenceChar }.count
        var body = Array(lines.dropFirst())
        if let last = body.last?.trimmingWhitespace(), last.count >= fenceLength, last.allSatisfy({ $0 == fenceChar }) {
            body.removeLast()
        }
        return body.joined(separator: "\n")
    }

    /// Markdown for `text` as a block of `kind`. `listIndent` is the whitespace that goes
    /// before a list marker, so nested items line up under their parent.
    static func render(_ text: String, as kind: BlockKind, listIndent: String = "", lineEnding: String = "\n")
        -> String
    {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        switch kind {
        case .paragraph:
            return escapeBlockStart(lines.joined(separator: lineEnding))
        case .heading(let level):
            let hashes = String(repeating: "#", count: min(max(level, 1), 6))
            let content = lines.map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }.joined(separator: " ")
            return content.isEmpty ? hashes : "\(hashes) \(content)"
        case .listItem(let item):
            return renderListItem(lines, item: item, indent: listIndent, lineEnding: lineEnding)
        case .blockquote:
            return lines.map { $0.isEmpty ? ">" : "> \($0)" }.joined(separator: lineEnding)
        case .codeBlock(let language):
            var fence = "```"
            while text.contains(fence) { fence += "`" }
            return ([fence + (language ?? "")] + lines + [fence]).joined(separator: lineEnding)
        case .thematicBreak:
            return "---"
        case .image:
            let trimmed = text.trimmingWhitespace()
            if trimmed.hasPrefix("![") { return trimmed }
            return "![\(trimmed)]()"
        case .table, .html, .mdx, .linkDefinitions:
            return lines.joined(separator: lineEnding)
        }
    }

    private static func renderListItem(_ lines: [String], item: ListItem, indent: String, lineEnding: String)
        -> String
    {
        var prefix: String
        switch item.marker {
        case .bullet: prefix = "- "
        case .ordered(let number): prefix = "\(number). "
        }
        let continuationIndent = indent + String(repeating: " ", count: prefix.count)
        switch item.checkbox {
        case .unchecked: prefix += "[ ] "
        case .checked: prefix += "[x] "
        case nil: break
        }
        let first = indent + prefix + (lines.first ?? "")
        let rest = lines.dropFirst().map { $0.isEmpty ? "" : continuationIndent + $0 }
        return ([first] + rest).joined(separator: lineEnding)
    }

    /// Splits a list item's first line into the width of its marker prefix (indent,
    /// marker, spaces) and the text after it, checkbox removed.
    private static func stripListMarker(_ line: String) -> (Int, String) {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" { index = line.index(after: index) }
        if index < line.endIndex, "-*+".contains(line[index]) {
            index = line.index(after: index)
        } else {
            while index < line.endIndex, line[index].isASCII, line[index].isNumber { index = line.index(after: index) }
            if index < line.endIndex, line[index] == "." || line[index] == ")" { index = line.index(after: index) }
        }
        var spaces = 0
        while index < line.endIndex, line[index] == " ", spaces < 4 {
            index = line.index(after: index)
            spaces += 1
        }
        let width = line.distance(from: line.startIndex, to: index)
        var rest = line[index...]
        for box in ["[ ] ", "[x] ", "[X] "] where rest.hasPrefix(box) {
            rest = rest.dropFirst(box.count)
        }
        if rest == "[ ]" || rest == "[x]" || rest == "[X]" { rest = "" }
        return (width, String(rest))
    }

    private static func dropLeadingSpaces(_ line: String, upTo count: Int) -> String {
        var text = Substring(line)
        var dropped = 0
        while dropped < count, text.first == " " {
            text = text.dropFirst()
            dropped += 1
        }
        return String(text)
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let trimmed = line.trimmingWhitespace()
        return !trimmed.isEmpty && (trimmed.allSatisfy { $0 == "=" } || trimmed.allSatisfy { $0 == "-" })
    }

    /// Escapes text that would otherwise open a different block (`# `, `- `, `1. `, `>`).
    private static func escapeBlockStart(_ text: String) -> String {
        let leading = text.prefix { $0 == " " }
        let rest = text.dropFirst(leading.count)
        guard let first = rest.first else { return text }
        if "#>-+*=".contains(first) || (first == "`" && rest.hasPrefix("```"))
            || (first == "~" && rest.hasPrefix("~~~"))
        {
            let reparsed = MarkdownParser.parse(text, flavor: .markdown, detectFrontmatter: false)
            if reparsed.blocks.count == 1, reparsed.blocks[0].kind == .paragraph { return text }
            return leading + "\\" + rest
        }
        if first.isNumber, let delimiter = rest.firstIndex(where: { !$0.isNumber }),
            rest[delimiter] == "." || rest[delimiter] == ")"
        {
            let reparsed = MarkdownParser.parse(text, flavor: .markdown, detectFrontmatter: false)
            if reparsed.blocks.count == 1, reparsed.blocks[0].kind == .paragraph { return text }
            return leading + rest[..<delimiter] + "\\" + rest[delimiter...]
        }
        return text
    }
}

extension StringProtocol {
    func trimmingWhitespace() -> String {
        String(self.drop { $0 == " " || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
    }
}
