/// Finds inline markdown (emphasis, code, links, images) in one block's text, for styling.
///
/// This is a styling pass, not a renderer: it follows CommonMark closely enough for the
/// editor (flanking rules, code spans hiding everything inside them, backslash escapes)
/// without its full delimiter algorithm. Offsets are UTF-16, relative to the text given.
public enum InlineScanner {
    public static func scan(_ text: String) -> [InlineSpan] {
        var scanner = Scan(Array(text.utf16))
        scanner.run()
        return scanner.spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

public struct InlineSpan: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case strong
        case emphasis
        case strikethrough
        case code
        case link(destination: String)
        case image(source: String)
        /// `<https://…>` or a bare `https://…` URL.
        case autolink(String)
    }

    public var kind: Kind
    /// The whole span, markers included.
    public var range: Range<Int>
    /// What the reader sees: the text between the markers.
    public var content: Range<Int>
    /// The syntax around the content (`**`, `` ` ``, `[`, `](url)`), which the editor dims
    /// or hides.
    public var markers: [Range<Int>]
}

private struct Scan {
    let chars: [UInt16]
    var spans: [InlineSpan] = []
    /// Characters already claimed by code spans, escapes and link destinations, which
    /// no other syntax may use.
    var masked: [Bool]

    init(_ chars: [UInt16]) {
        self.chars = chars
        masked = Array(repeating: false, count: chars.count)
    }

    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let backtick = UInt16(UInt8(ascii: "`"))
    static let star = UInt16(UInt8(ascii: "*"))
    static let underscore = UInt16(UInt8(ascii: "_"))
    static let tilde = UInt16(UInt8(ascii: "~"))
    static let openBracket = UInt16(UInt8(ascii: "["))
    static let closeBracket = UInt16(UInt8(ascii: "]"))
    static let openParen = UInt16(UInt8(ascii: "("))
    static let closeParen = UInt16(UInt8(ascii: ")"))
    static let bang = UInt16(UInt8(ascii: "!"))
    static let less = UInt16(UInt8(ascii: "<"))
    static let greater = UInt16(UInt8(ascii: ">"))

    mutating func run() {
        maskEscapes()
        scanCodeSpans()
        scanAutolinks()
        scanLinks()
        scanBareURLs()
        scanDelimited(Self.star, length: 2, kind: .strong)
        scanDelimited(Self.underscore, length: 2, kind: .strong)
        scanDelimited(Self.tilde, length: 2, kind: .strikethrough)
        scanDelimited(Self.star, length: 1, kind: .emphasis)
        scanDelimited(Self.underscore, length: 1, kind: .emphasis)
    }

    private func string(_ range: Range<Int>) -> String {
        String(decoding: chars[range], as: UTF16.self)
    }

    private mutating func mask(_ range: Range<Int>) {
        for index in range { masked[index] = true }
    }

    private func isPunctuation(_ char: UInt16) -> Bool {
        char < 128 && "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".utf16.contains(char)
    }

    private func isWhitespace(_ char: UInt16?) -> Bool {
        guard let char else { return true }
        return char == 32 || char == 9 || char == 10 || char == 13 || char == 0xA0
    }

    // MARK: - Escapes and code

    private mutating func maskEscapes() {
        var index = 0
        while index + 1 < chars.count {
            if chars[index] == Self.backslash, isPunctuation(chars[index + 1]) {
                mask(index..<(index + 2))
                index += 2
            } else {
                index += 1
            }
        }
    }

    private mutating func scanCodeSpans() {
        var index = 0
        while index < chars.count {
            guard chars[index] == Self.backtick, !masked[index] else {
                index += 1
                continue
            }
            let runLength = run(of: Self.backtick, from: index)
            var search = index + runLength
            var closed = false
            while search < chars.count {
                if chars[search] == Self.backtick {
                    let closing = run(of: Self.backtick, from: search)
                    if closing == runLength {
                        let range = index..<(search + closing)
                        spans.append(
                            InlineSpan(
                                kind: .code, range: range, content: (index + runLength)..<search,
                                markers: [index..<(index + runLength), search..<(search + closing)]))
                        mask(range)
                        index = search + closing
                        closed = true
                        break
                    }
                    search += closing
                } else {
                    search += 1
                }
            }
            if !closed { index += runLength }
        }
    }

    private func run(of char: UInt16, from start: Int) -> Int {
        var end = start
        while end < chars.count, chars[end] == char { end += 1 }
        return end - start
    }

    // MARK: - Links

    private mutating func scanAutolinks() {
        var index = 0
        while index < chars.count {
            guard chars[index] == Self.less, !masked[index],
                let close = chars[(index + 1)...].firstIndex(where: { $0 == Self.greater || isWhitespace($0) }),
                chars[close] == Self.greater
            else {
                index += 1
                continue
            }
            let inner = string((index + 1)..<close)
            if inner.contains(":") || inner.contains("@") {
                let range = index..<(close + 1)
                spans.append(
                    InlineSpan(
                        kind: .autolink(inner), range: range, content: (index + 1)..<close,
                        markers: [index..<(index + 1), close..<(close + 1)]))
                mask(range)
                index = close + 1
            } else {
                index += 1
            }
        }
    }

    private mutating func scanLinks() {
        var index = 0
        while index < chars.count {
            guard chars[index] == Self.openBracket, !masked[index] else {
                index += 1
                continue
            }
            let isImage = index > 0 && chars[index - 1] == Self.bang && !masked[index - 1]
            guard let closeBracket = matchingBracket(from: index),
                closeBracket + 1 < chars.count, chars[closeBracket + 1] == Self.openParen,
                let closeParen = matchingParen(from: closeBracket + 1)
            else {
                index += 1
                continue
            }
            let destination = linkDestination((closeBracket + 2)..<closeParen)
            let start = isImage ? index - 1 : index
            let range = start..<(closeParen + 1)
            spans.append(
                InlineSpan(
                    kind: isImage ? .image(source: destination) : .link(destination: destination),
                    range: range, content: (index + 1)..<closeBracket,
                    markers: [start..<(index + 1), closeBracket..<(closeParen + 1)]))
            mask(closeBracket..<(closeParen + 1))
            if isImage { mask(range) }
            index = closeParen + 1
        }
    }

    /// The URL part of `(url "title")`, without angle brackets or the title.
    private func linkDestination(_ range: Range<Int>) -> String {
        var text = Substring(string(range)).drop { $0 == " " }
        if text.first == "<", let end = text.firstIndex(of: ">") {
            return String(text[text.index(after: text.startIndex)..<end])
        }
        if let space = text.firstIndex(of: " ") { text = text[..<space] }
        return String(text)
    }

    private func matchingBracket(from open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < chars.count {
            if !masked[index] || chars[index] == Self.openBracket || chars[index] == Self.closeBracket {
                if chars[index] == Self.openBracket, !isEscaped(index) {
                    depth += 1
                } else if chars[index] == Self.closeBracket, !isEscaped(index) {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index += 1
        }
        return nil
    }

    private func matchingParen(from open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < chars.count {
            let char = chars[index]
            if char == Self.openParen, !isEscaped(index) {
                depth += 1
            } else if char == Self.closeParen, !isEscaped(index) {
                depth -= 1
                if depth == 0 { return index }
            } else if char == 10 {
                return nil
            }
            index += 1
        }
        return nil
    }

    private func isEscaped(_ index: Int) -> Bool {
        index > 0 && chars[index - 1] == Self.backslash && masked[index - 1]
    }

    private mutating func scanBareURLs() {
        let text = string(0..<chars.count)
        for prefix in ["https://", "http://"] {
            var searchStart = text.startIndex
            while let found = text.range(of: prefix, range: searchStart..<text.endIndex) {
                let start = text.utf16.distance(from: text.utf16.startIndex, to: found.lowerBound)
                searchStart = found.upperBound
                guard !masked[start], start == 0 || isWhitespace(chars[start - 1]) || chars[start - 1] == Self.openParen
                else { continue }
                var end = start
                while end < chars.count, !isWhitespace(chars[end]), chars[end] != Self.less { end += 1 }
                // Trailing punctuation belongs to the sentence, not the URL.
                while end > start, ".,:;!?)\"'".utf16.contains(chars[end - 1]) { end -= 1 }
                guard end > start + prefix.utf16.count, !masked[start..<end].contains(true) else { continue }
                let range = start..<end
                spans.append(InlineSpan(kind: .autolink(string(range)), range: range, content: range, markers: []))
                mask(range)
            }
        }
    }
}

extension Scan {
    /// Pairs runs of `char` (exactly `length` long within the run's usable part) that open
    /// and close by CommonMark's flanking rules.
    private mutating func scanDelimited(_ char: UInt16, length: Int, kind: InlineSpan.Kind) {
        var index = 0
        while index < chars.count {
            guard chars[index] == char, !masked[index], canOpen(at: index, char: char, length: length) else {
                index += 1
                continue
            }
            var search = index + length
            var matched = false
            while search + length <= chars.count {
                if chars[search] == Self.backtick
                    || chars[search] == 10 && search + 1 < chars.count
                        && chars[search + 1] == 10
                {
                    break
                }
                if chars[search] == char, !masked[search], search > index + length,
                    canClose(at: search, char: char, length: length)
                {
                    let range = index..<(search + length)
                    spans.append(
                        InlineSpan(
                            kind: kind, range: range, content: (index + length)..<search,
                            markers: [index..<(index + length), search..<(search + length)]))
                    mask(index..<(index + length))
                    mask(search..<(search + length))
                    index = search + length
                    matched = true
                    break
                }
                search += 1
            }
            if !matched { index += 1 }
        }
    }

    private func canOpen(at index: Int, char: UInt16, length: Int) -> Bool {
        guard index + length <= chars.count, (index..<(index + length)).allSatisfy({ chars[$0] == char && !masked[$0] })
        else { return false }
        if length == 1 {
            // A single delimiter can't open from inside a longer run.
            if index > 0, chars[index - 1] == char, !masked[index - 1] { return false }
            if index + 1 < chars.count, chars[index + 1] == char, !masked[index + 1] { return false }
        }
        let before = index > 0 ? chars[index - 1] : nil
        let after = index + length < chars.count ? chars[index + length] : nil
        guard !isWhitespace(after) else { return false }
        if char == Self.underscore, let before, !isWhitespace(before), !isPunctuation(before) { return false }
        return true
    }

    private func canClose(at index: Int, char: UInt16, length: Int) -> Bool {
        guard index + length <= chars.count, (index..<(index + length)).allSatisfy({ chars[$0] == char && !masked[$0] })
        else { return false }
        if length == 1 {
            if index > 0, chars[index - 1] == char, !masked[index - 1] { return false }
            if index + 1 < chars.count, chars[index + 1] == char, !masked[index + 1] { return false }
        }
        let before = index > 0 ? chars[index - 1] : nil
        let after = index + length < chars.count ? chars[index + length] : nil
        guard !isWhitespace(before) else { return false }
        if char == Self.underscore, let after, !isWhitespace(after), !isPunctuation(after) { return false }
        return true
    }
}
