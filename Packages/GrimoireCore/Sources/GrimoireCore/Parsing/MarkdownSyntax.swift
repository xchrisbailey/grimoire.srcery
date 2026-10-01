/// Measures the markers at the start of a markdown line. Lengths are UTF-16 units.
public enum MarkdownSyntax {
    /// The parts of a list item's first line before its text.
    public struct ListPrefix: Equatable, Sendable {
        /// Leading spaces or tabs.
        public var indent: Int
        /// The bullet or number with its delimiter, plus the spaces after it.
        public var marker: Int
        /// `[ ] ` or `[x] ` (with its space), or 0 for a plain item.
        public var checkbox: Int

        public var length: Int { indent + marker + checkbox }
    }

    public static func listPrefix(in line: String) -> ListPrefix {
        let utf16 = Array(line.utf16)
        var index = 0
        while index < utf16.count, utf16[index] == space || utf16[index] == tab { index += 1 }
        let indent = index
        if index < utf16.count, "-*+".utf16.contains(utf16[index]) {
            index += 1
        } else {
            while index < utf16.count, (48...57).contains(utf16[index]) { index += 1 }
            if index < utf16.count, utf16[index] == period || utf16[index] == closeParen { index += 1 }
        }
        var spaces = 0
        while index < utf16.count, utf16[index] == space, spaces < 4 {
            index += 1
            spaces += 1
        }
        let marker = index - indent
        let rest = String(decoding: utf16[index...], as: UTF16.self)
        if ["[ ] ", "[x] ", "[X] "].contains(where: rest.hasPrefix) {
            return ListPrefix(indent: indent, marker: marker, checkbox: 4)
        }
        if ["[ ]", "[x]", "[X]"].contains(rest) { return ListPrefix(indent: indent, marker: marker, checkbox: 3) }
        return ListPrefix(indent: indent, marker: marker, checkbox: 0)
    }

    /// Length of a quote line's `>` marker and the space after it, or 0.
    public static func quoteMarker(in line: String) -> Int {
        let utf16 = Array(line.utf16)
        var index = 0
        while index < utf16.count, index < 3, utf16[index] == space { index += 1 }
        guard index < utf16.count, utf16[index] == greater else { return 0 }
        index += 1
        if index < utf16.count, utf16[index] == space { index += 1 }
        return index
    }

    /// The ATX heading markers on a line: the leading `#`s with the spaces after them, and
    /// where an optional closing run of `#`s starts (the line's length when there's none).
    public static func headingMarkers(in line: String) -> (prefix: Int, suffixStart: Int) {
        let utf16 = Array(line.utf16)
        var prefix = 0
        while prefix < utf16.count, utf16[prefix] == space { prefix += 1 }
        while prefix < utf16.count, utf16[prefix] == hash { prefix += 1 }
        while prefix < utf16.count, utf16[prefix] == space || utf16[prefix] == tab { prefix += 1 }
        var end = utf16.count
        while end > prefix, utf16[end - 1] == space { end -= 1 }
        var hashes = end
        while hashes > prefix, utf16[hashes - 1] == hash { hashes -= 1 }
        let hasClosing = hashes < end && hashes > prefix && utf16[hashes - 1] == space
        return (prefix, hasClosing ? hashes - 1 : utf16.count)
    }

    /// Whether a code block's source opens with a fence rather than indentation.
    public static func isFenced(_ source: String) -> Bool {
        let first = source.prefix { !$0.isNewline }.drop { $0 == " " }
        return first.hasPrefix("```") || first.hasPrefix("~~~")
    }

    private static let space = UInt16(UInt8(ascii: " "))
    private static let tab = UInt16(UInt8(ascii: "\t"))
    private static let period = UInt16(UInt8(ascii: "."))
    private static let closeParen = UInt16(UInt8(ascii: ")"))
    private static let greater = UInt16(UInt8(ascii: ">"))
    private static let hash = UInt16(UInt8(ascii: "#"))
}
