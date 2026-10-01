import Foundation

/// A markdown file as optional frontmatter plus an ordered list of blocks.
///
/// `markdown` concatenates every block's source and trailing text, so an unedited
/// document serializes to exactly the text it was parsed from.
public struct Document: Hashable, Sendable {
    public var flavor: DocumentFlavor
    public var frontmatter: Frontmatter?
    /// Blank lines before the first block (after the frontmatter, if any).
    public var leading: String
    public var blocks: [Block]
    /// The line break new blocks use, taken from the first one in the file.
    public var lineEnding: String

    public init(
        flavor: DocumentFlavor = .markdown,
        frontmatter: Frontmatter? = nil,
        leading: String = "",
        blocks: [Block] = [],
        lineEnding: String = "\n"
    ) {
        self.flavor = flavor
        self.frontmatter = frontmatter
        self.leading = leading
        self.blocks = blocks
        self.lineEnding = lineEnding
    }

    public init(parsing text: String, flavor: DocumentFlavor = .markdown) {
        self = MarkdownParser.parse(text, flavor: flavor)
    }

    /// The document serialized back to markdown.
    public var markdown: String {
        var out = ""
        if let frontmatter {
            out += frontmatter.source
            out += frontmatter.trailing
        }
        out += leading
        for block in blocks {
            out += block.source
            out += block.trailing
        }
        return out
    }
}

public enum DocumentFlavor: Hashable, Sendable {
    case markdown
    case mdx

    public init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "mdx": self = .mdx
        default: return nil
        }
    }
}

/// YAML frontmatter, kept as raw source.
public struct Frontmatter: Hashable, Sendable {
    /// From the opening `---` through the closing fence, without its line break.
    public var source: String
    public var trailing: String

    public init(source: String, trailing: String) {
        self.source = source
        self.trailing = trailing
    }

    /// The value of a top-level `key: value` line, without quotes. Enough for simple keys
    /// like `lang` or `title`; it isn't a YAML parser.
    public func value(forKey key: String) -> String? {
        for line in yaml.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":"),
                line[..<colon].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The YAML between the fences.
    public var yaml: String {
        var lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return "" }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }
}
