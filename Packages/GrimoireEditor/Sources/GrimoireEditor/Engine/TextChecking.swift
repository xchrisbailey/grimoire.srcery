import Foundation
import GrimoireCore

/// Which of the system's spelling, grammar and substitution checks run in the editor.
public struct TextChecking: Equatable, Sendable {
    public var spelling = true
    public var grammar = true
    public var correction = true
    public var smartQuotes = true
    public var smartDashes = true
    public var textReplacement = true

    public init(
        spelling: Bool = true, grammar: Bool = true, correction: Bool = true, smartQuotes: Bool = true,
        smartDashes: Bool = true, textReplacement: Bool = true
    ) {
        self.spelling = spelling
        self.grammar = grammar
        self.correction = correction
        self.smartQuotes = smartQuotes
        self.smartDashes = smartDashes
        self.textReplacement = textReplacement
    }

    /// Only the spelling underline: what a fresh editor does before settings arrive.
    public static let spellingOnly = TextChecking(
        grammar: false, correction: false, smartQuotes: false, smartDashes: false, textReplacement: false)
}

/// The parts of a markdown file that aren't prose, so spelling, grammar, smart quotes and
/// autocorrect leave them alone: frontmatter, code (blocks and spans), HTML and MDX,
/// link destinations, URLs and link definitions.
public enum ProseExclusions {
    /// Excluded ranges that touch `range`, in order. Offsets are UTF-16.
    public static func ranges(in range: NSRange, text: NSString, index: BlockIndex) -> [NSRange] {
        var excluded: [NSRange] = []
        if let frontmatter = index.frontmatterRange {
            excluded.append(NSRange(location: 0, length: frontmatter.upperBound))
        }
        let end = min(NSMaxRange(range), text.length)
        let blocks = index.blockIndices(overlapping: range.location..<max(range.location + 1, end))
        for position in blocks where position < index.blocks.count {
            let source = NSRange(index.sourceRange(of: position))
            guard NSMaxRange(source) <= text.length else { continue }
            switch index.blocks[position].kind {
            case .codeBlock, .html, .mdx, .linkDefinitions:
                excluded.append(source)
            default:
                excluded += inlineCode(in: source, text: text)
            }
        }
        return excluded.filter { NSIntersectionRange($0, range).length > 0 || NSLocationInRange(range.location, $0) }
    }

    /// Code spans, URLs, link destinations and image sources inside one block.
    private static func inlineCode(in source: NSRange, text: NSString) -> [NSRange] {
        InlineScanner.scan(text.substring(with: source)).compactMap { span in
            let shift = { (range: Range<Int>) in
                NSRange(location: source.location + range.lowerBound, length: range.count)
            }
            switch span.kind {
            case .code, .autolink: return shift(span.range)
            case .link, .image: return span.markers.last.map(shift)
            default: return nil
            }
        }
    }

    /// Whether `range` overlaps any of `excluded`.
    public static func overlaps(_ range: NSRange, _ excluded: [NSRange]) -> Bool {
        excluded.contains {
            NSIntersectionRange($0, range).length > 0 || (range.length == 0 && NSLocationInRange(range.location, $0))
        }
    }
}
