/// The MDX pre-pass: finds top-level `import` / `export` statements and JSX elements
/// so they can be kept as opaque blocks before the rest goes to the markdown parser.
///
/// A region must start at column 0 after a blank line (or another region), never inside
/// a fenced code block. JSX inside a paragraph stays literal text.
struct MDXScanner {
    let lines: Lines

    private var bytes: [UInt8] { lines.bytes }

    func regions(from start: Int) -> [Range<Int>] {
        var regions: [Range<Int>] = []
        var fence: (char: UInt8, length: Int)?
        var atBlockStart = true
        var line = lines.line(containing: start)
        if lines.starts[line] < start { line += 1 }

        while line < lines.count {
            let lineStart = lines.starts[line]
            let content = Array(bytes[lineStart..<lines.contentEnd(ofLine: line)])

            if let open = fence {
                if let close = Self.fenceRun(content), close.char == open.char, close.length >= open.length,
                    content.allSatisfy({ $0 == close.char || $0 == 0x20 || $0 == 0x09 })
                {
                    fence = nil
                }
                line += 1
                atBlockStart = false
                continue
            }
            if let open = Self.fenceRun(content) {
                fence = open
                line += 1
                atBlockStart = false
                continue
            }
            if lines.isBlank(line: line) {
                atBlockStart = true
                line += 1
                continue
            }

            if atBlockStart, let lastLine = regionEnd(startingAt: line, content: content) {
                regions.append(lineStart..<lines.contentEnd(ofLine: lastLine))
                line = lastLine + 1
                atBlockStart = true
                continue
            }
            atBlockStart = false
            line += 1
        }
        return regions
    }

    /// The last line of an MDX region that starts on `line`, or nil if it isn't one.
    private func regionEnd(startingAt line: Int, content: [UInt8]) -> Int? {
        if Self.hasPrefix(content, "import") || Self.hasPrefix(content, "export") {
            return lineBeforeBlank(after: line)
        }
        guard content.count >= 2, content[0] == UInt8(ascii: "<") else { return nil }
        let next = content[1]
        guard next == UInt8(ascii: ">") || Self.isLetter(next) else { return nil }
        if let end = jsxEnd(from: lines.starts[line]) {
            return lines.line(containing: max(end - 1, lines.starts[line]))
        }
        return lineBeforeBlank(after: line)
    }

    private func lineBeforeBlank(after line: Int) -> Int {
        var last = line
        while last + 1 < lines.count, !lines.isBlank(line: last + 1) { last += 1 }
        return last
    }

    /// Offset just past the tag that closes the JSX element opening at `start`, or nil
    /// when it never closes.
    private func jsxEnd(from start: Int) -> Int? {
        let root = tagName(at: start + 1)
        var depth = 0
        var index = start
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            let closing = index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/")
            let nameStart = closing ? index + 2 : index + 1
            let name = tagName(at: nameStart)
            let isTag =
                nameStart < bytes.count
                && (Self.isLetter(bytes[nameStart]) || bytes[nameStart] == UInt8(ascii: ">"))
            guard isTag, let tagEnd = tagEnd(from: nameStart) else {
                index += 1
                continue
            }
            if name == root {
                if closing {
                    depth -= 1
                } else if bytes[tagEnd - 2] != UInt8(ascii: "/") {
                    depth += 1
                }
                if depth <= 0 { return tagEnd }
            }
            index = tagEnd
        }
        return nil
    }

    private func tagName(at start: Int) -> [UInt8] {
        var end = start
        while end < bytes.count,
            Self.isLetter(bytes[end]) || (bytes[end] >= 0x30 && bytes[end] <= 0x39)
                || [UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: ":")].contains(bytes[end])
        {
            end += 1
        }
        return Array(bytes[start..<end])
    }

    /// Offset just past the `>` that ends a tag, skipping quoted strings and `{…}`.
    private func tagEnd(from start: Int) -> Int? {
        var quote: UInt8?
        var braces = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "{") {
                braces += 1
            } else if byte == UInt8(ascii: "}") {
                braces -= 1
            } else if byte == UInt8(ascii: ">"), braces <= 0 {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    /// A code fence opening a line (up to three spaces in): its character and length.
    private static func fenceRun(_ content: [UInt8]) -> (char: UInt8, length: Int)? {
        var index = 0
        while index < content.count, index < 3, content[index] == 0x20 { index += 1 }
        guard index < content.count else { return nil }
        let char = content[index]
        guard char == UInt8(ascii: "`") || char == UInt8(ascii: "~") else { return nil }
        var length = 0
        while index + length < content.count, content[index + length] == char { length += 1 }
        return length >= 3 ? (char, length) : nil
    }

    private static func hasPrefix(_ content: [UInt8], _ keyword: String) -> Bool {
        let word = Array(keyword.utf8)
        guard content.count > word.count, Array(content[0..<word.count]) == word else { return false }
        let next = content[word.count]
        return next == 0x20 || next == 0x09 || next == UInt8(ascii: "{") || next == UInt8(ascii: "*")
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }
}
