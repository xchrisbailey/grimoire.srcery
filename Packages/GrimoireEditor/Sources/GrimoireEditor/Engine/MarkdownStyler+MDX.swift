import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// MDX blocks, shown as their source: tags and `import` / `export` keywords in the MDX
/// color, attribute names in the attribute color, strings green, everything else ink.
extension MarkdownStyler {
    func styleMDX(_ range: NSRange, in storage: NSMutableAttributedString, raw: Bool) {
        if !raw { storage.addAttributes([.font: theme.code, .foregroundColor: theme.ink], range: range) }
        for piece in MDXHighlighter.pieces(in: (storage.string as NSString).substring(with: range)) {
            let pieceRange = NSRange(location: range.location + piece.range.lowerBound, length: piece.range.count)
            if raw {
                applyRaw(piece.token, to: pieceRange, in: storage)
            } else {
                storage.addAttributes(theme.token(piece.token, raw: false).attributes, range: pieceRange)
            }
        }
    }
}

/// Finds the parts of MDX source a theme colors. Offsets are UTF-16.
struct MDXHighlighter {
    struct Piece: Equatable {
        var token: MarkdownToken
        var range: Range<Int>
    }

    static let keywords: Set<String> = ["import", "export", "from", "default", "const", "let", "as", "function"]

    static func pieces(in source: String) -> [Piece] {
        var highlighter = MDXHighlighter(chars: Array(source.utf16))
        highlighter.run()
        return highlighter.pieces
    }

    private let chars: [UInt16]
    private var pieces: [Piece] = []
    private var index = 0

    private init(chars: [UInt16]) {
        self.chars = chars
    }

    private static let newline: UInt16 = 10, space: UInt16 = 32, tab: UInt16 = 9
    private static let less = UInt16(UInt8(ascii: "<")), greater = UInt16(UInt8(ascii: ">"))
    private static let slash = UInt16(UInt8(ascii: "/")), openBrace = UInt16(UInt8(ascii: "{"))
    private static let closeBrace = UInt16(UInt8(ascii: "}")), backslash = UInt16(UInt8(ascii: "\\"))
    private static let quotes: Set<UInt16> = [34, 39, 96]

    private mutating func run() {
        var lineStart = true
        while index < chars.count {
            let char = chars[index]
            if char == Self.newline {
                lineStart = true
                index += 1
            } else if char == Self.less, startsTag(at: index) {
                lineStart = false
                tag()
            } else if lineStart, char != Self.space, char != Self.tab {
                lineStart = false
                if !statement() { index += 1 }
            } else if char == Self.openBrace {
                index = endOfBraces(at: index)
            } else {
                index += 1
            }
        }
    }

    /// `<Name`, `</Name` or the fragment `<>`.
    private func startsTag(at start: Int) -> Bool {
        guard start + 1 < chars.count else { return false }
        let next = chars[start + 1]
        return isNameChar(next) || next == Self.slash || next == Self.greater
    }

    /// A tag from `<` to its closing `>` or `/>`: name, attributes and string values.
    private mutating func tag() {
        let start = index
        var end = index + 1
        if chars[end] == Self.slash { end += 1 }
        end = endOfWord(at: end)
        if end < chars.count, chars[end] == Self.greater {
            pieces.append(Piece(token: .mdx, range: start..<(end + 1)))
            index = end + 1
            return
        }
        pieces.append(Piece(token: .mdx, range: start..<end))
        index = end
        while index < chars.count {
            let char = chars[index]
            if char == Self.greater
                || (char == Self.slash && index + 1 < chars.count && chars[index + 1] == Self.greater)
            {
                let close = char == Self.greater ? index + 1 : index + 2
                pieces.append(Piece(token: .mdx, range: index..<close))
                index = close
                return
            }
            if Self.quotes.contains(char) {
                let close = endOfString(at: index)
                pieces.append(Piece(token: .mdxString, range: index..<close))
                index = close
            } else if char == Self.openBrace {
                index = endOfBraces(at: index)
            } else if isNameChar(char) {
                let close = endOfWord(at: index)
                pieces.append(Piece(token: .mdxAttribute, range: index..<close))
                index = close
            } else {
                index += 1
            }
        }
    }

    /// An `import` / `export` line: keywords in the MDX color and strings green. False when
    /// the line doesn't start with a keyword.
    private mutating func statement() -> Bool {
        let first = endOfWord(at: index)
        guard first > index, Self.keywords.contains(word(index..<first)) else { return false }
        while index < chars.count, chars[index] != Self.newline {
            if Self.quotes.contains(chars[index]) {
                let close = endOfString(at: index)
                pieces.append(Piece(token: .mdxString, range: index..<close))
                index = close
                continue
            }
            let end = endOfWord(at: index)
            guard end > index else {
                index += 1
                continue
            }
            if Self.keywords.contains(word(index..<end)) { pieces.append(Piece(token: .mdx, range: index..<end)) }
            index = end
        }
        return true
    }

    private func isNameChar(_ char: UInt16) -> Bool {
        (48...57).contains(char) || (65...90).contains(char) || (97...122).contains(char)
            || [95, 45, 46, 58, 36].contains(char)
    }

    private func word(_ range: Range<Int>) -> String {
        String(decoding: chars[range], as: UTF16.self)
    }

    private func endOfWord(at start: Int) -> Int {
        var end = start
        while end < chars.count, isNameChar(chars[end]) { end += 1 }
        return end
    }

    private func endOfString(at start: Int) -> Int {
        let quote = chars[start]
        var end = start + 1
        while end < chars.count, chars[end] != quote, chars[end] != Self.newline {
            end += chars[end] == Self.backslash ? 2 : 1
        }
        return min(end + 1, chars.count)
    }

    private func endOfBraces(at start: Int) -> Int {
        var depth = 0
        var end = start
        while end < chars.count {
            if chars[end] == Self.openBrace { depth += 1 }
            if chars[end] == Self.closeBrace {
                depth -= 1
                if depth == 0 { return end + 1 }
            }
            end += 1
        }
        return end
    }
}
