/// Line-level view of UTF-8 bytes, using the same line endings as cmark (`\n`, `\r\n`, `\r`).
struct Lines {
    let bytes: [UInt8]
    /// Byte offset where each line starts. Always has at least one entry.
    let starts: [Int]

    private static let lf = UInt8(ascii: "\n")
    private static let cr = UInt8(ascii: "\r")
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        var starts = [0]
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Self.lf {
                starts.append(index + 1)
            } else if byte == Self.cr {
                if index + 1 < bytes.count, bytes[index + 1] == Self.lf { index += 1 }
                starts.append(index + 1)
            }
            index += 1
        }
        self.starts = starts
    }

    var count: Int { starts.count }

    /// Offset for a 1-based cmark line and byte column, clamped to the text.
    func offset(line: Int, column: Int) -> Int {
        guard line >= 1 else { return 0 }
        guard line <= starts.count else { return bytes.count }
        return min(starts[line - 1] + max(column - 1, 0), bytes.count)
    }

    /// Index of the line containing `offset`.
    func line(containing offset: Int) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// End of a line's content, before its line break.
    func contentEnd(ofLine line: Int) -> Int {
        var end = line + 1 < starts.count ? starts[line + 1] : bytes.count
        if end > starts[line], bytes[end - 1] == Self.lf { end -= 1 }
        if end > starts[line], bytes[end - 1] == Self.cr { end -= 1 }
        return end
    }

    func isBlank(line: Int) -> Bool {
        bytes[starts[line]..<contentEnd(ofLine: line)].allSatisfy { $0 == Self.space || $0 == Self.tab }
    }

    /// Moves `offset` back to the start of its line when only spaces and tabs precede it.
    func lineStartIfIndented(_ offset: Int) -> Int {
        let start = starts[line(containing: offset)]
        return bytes[start..<offset].allSatisfy { $0 == Self.space || $0 == Self.tab } ? start : offset
    }

    /// Start of the first line in `range` holding something other than whitespace.
    func firstNonBlank(in range: Range<Int>) -> Int? {
        guard !range.isEmpty else { return nil }
        var line = line(containing: range.lowerBound)
        while line < starts.count, starts[line] < range.upperBound {
            let from = max(starts[line], range.lowerBound)
            let to = min(contentEnd(ofLine: line), range.upperBound)
            if from < to, bytes[from..<to].contains(where: { $0 != Self.space && $0 != Self.tab }) {
                return max(starts[line], range.lowerBound)
            }
            line += 1
        }
        return nil
    }

    /// Where a block's content ends and its trailing line break and blank lines begin:
    /// the end of the last line in `range` that isn't blank.
    func splitTrailing(_ range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        let firstLine = line(containing: range.lowerBound)
        var line = line(containing: range.upperBound - 1)
        while line >= firstLine {
            let from = max(starts[line], range.lowerBound)
            let to = min(contentEnd(ofLine: line), range.upperBound)
            if from < to, bytes[from..<to].contains(where: { $0 != Self.space && $0 != Self.tab }) {
                return to
            }
            line -= 1
        }
        return range.lowerBound
    }

    /// The first line break in the text, if any.
    func firstLineEnding() -> String? {
        guard starts.count > 1 else { return nil }
        let end = starts[1]
        return end >= 2 && bytes[end - 2] == Self.cr && bytes[end - 1] == Self.lf
            ? "\r\n" : String(UnicodeScalar(bytes[end - 1]))
    }

    /// End offset (after the line break) of YAML frontmatter that opens the text:
    /// a `---` line, then a closing `---` or `...` line.
    func frontmatterEnd() -> Int? {
        guard starts.count > 1, text(ofLine: 0) == "---" else { return nil }
        for line in 1..<starts.count {
            let text = text(ofLine: line)
            if text == "---" || text == "..." {
                return line + 1 < starts.count ? starts[line + 1] : bytes.count
            }
        }
        return nil
    }

    func text(ofLine line: Int) -> String {
        var text = String(decoding: bytes[starts[line]..<contentEnd(ofLine: line)], as: UTF8.self)
        while text.last == " " || text.last == "\t" { text.removeLast() }
        return text
    }
}
