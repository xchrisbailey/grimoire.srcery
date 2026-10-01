import Foundation
import GrimoireCore

/// An AI command the editor hands to the app: what to read, and where the result goes.
/// The result replaces `range` (which includes any `/spell` typed), wrapped in `prefix` and
/// `suffix` so it sits on its own lines.
public struct IntelligenceCast: Equatable, Sendable {
    /// The spell or action: `continue`, `summarize`, `outline`, `tabulate`, `actions`,
    /// `translate`, `rewrite`, `shorten`, `expand` or `explain`.
    public var command: String
    /// The text the command reads.
    public var source: String
    public var range: NSRange
    public var prefix: String
    public var suffix: String
    /// The target language, for Translate.
    public var language: String?
    /// The code's language, for Explain Code.
    public var codeLanguage: String?

    public init(
        command: String, source: String, range: NSRange, prefix: String = "", suffix: String = "",
        language: String? = nil, codeLanguage: String? = nil
    ) {
        self.command = command
        self.source = source
        self.range = range
        self.prefix = prefix
        self.suffix = suffix
        self.language = language
        self.codeLanguage = codeLanguage
    }

    /// `text` as it goes into the document.
    public func wrap(_ text: String) -> String {
        prefix + text + suffix
    }
}

/// Works out what an AI spell reads and replaces, from where it was typed.
public struct IntelligencePlanner {
    public let text: NSString
    public let index: BlockIndex

    public init(text: String, index: BlockIndex) {
        self.text = text as NSString
        self.index = index
    }

    /// The plan for spell `command` typed at `trigger` (the `/` and the query after it).
    public func plan(_ command: String, trigger: Range<Int>, language: String? = nil) -> IntelligenceCast {
        let trigger = NSRange(trigger)
        let line = lineRange(at: trigger.location)
        let before = text.substring(with: NSRange(location: line.location, length: trigger.location - line.location))
        let after = text.substring(
            with: NSRange(location: NSMaxRange(trigger), length: NSMaxRange(line) - NSMaxRange(trigger)))
        let rest = (before + after).trimmingCharacters(in: .whitespaces)
        switch command {
        case "continue":
            // The service spaces the continuation from the text before it.
            return IntelligenceCast(command: command, source: text.substring(to: trigger.location), range: trigger)
        case "summarize", "actions":
            return blockCast(command, source: section(before: trigger.location), line: line, rest: before + after)
        case "outline":
            let topic = rest.isEmpty ? previousBlock(before: line.location)?.text ?? "" : rest
            return lineCast(command, source: topic, line: line)
        default:
            // Table from text and Translate: the line's own text, else the block above.
            if !rest.isEmpty {
                return lineCast(command, source: rest, line: line, language: language)
            }
            guard let above = previousBlock(before: line.location) else {
                return lineCast(command, source: "", line: line, language: language)
            }
            let range = NSRange(location: above.range.location, length: NSMaxRange(line) - above.range.location)
            return IntelligenceCast(command: command, source: above.text, range: range, language: language)
        }
    }

    /// A plan for a selection action: rewrite, shorten, expand, or explain the code block.
    public func plan(action: String, selection: NSRange) -> IntelligenceCast? {
        if action == "explain" {
            guard let position = index.blockIndex(at: selection.location),
                case .codeBlock(let codeLanguage) = index.blocks[position].kind
            else { return nil }
            let block = NSRange(index.sourceRange(of: position))
            let code = index.blocks[position].text
            let end = NSMaxRange(block)
            return IntelligenceCast(
                command: action, source: code, range: NSRange(location: end, length: 0), prefix: "\n\n",
                codeLanguage: codeLanguage)
        }
        guard selection.length > 0 else { return nil }
        return IntelligenceCast(command: action, source: text.substring(with: selection), range: selection)
    }

    // MARK: - Pieces

    private func lineRange(at offset: Int) -> NSRange {
        var start = 0
        var end = 0
        text.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: offset, length: 0))
        return NSRange(location: start, length: end - start)
    }

    /// Replaces the whole line with a block.
    private func lineCast(_ command: String, source: String, line: NSRange, language: String? = nil)
        -> IntelligenceCast
    {
        IntelligenceCast(
            command: command, source: source, range: line, prefix: blankBefore(line) ? "" : "\n",
            suffix: blankAfter(line) ? "" : "\n", language: language)
    }

    /// Puts a block on the line, keeping any other text that was on it first.
    private func blockCast(_ command: String, source: String, line: NSRange, rest: String) -> IntelligenceCast {
        let kept = rest.trimmingCharacters(in: .whitespaces)
        var cast = lineCast(command, source: source, line: line)
        if !kept.isEmpty { cast.prefix = kept + "\n\n" }
        return cast
    }

    private func blankBefore(_ line: NSRange) -> Bool {
        guard line.location > 0 else { return true }
        let previous = lineRange(at: line.location - 1)
        return text.substring(with: previous).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func blankAfter(_ line: NSRange) -> Bool {
        let next = NSMaxRange(line) + 1
        guard next < text.length else { return true }
        return text.substring(with: lineRange(at: next)).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The text from the nearest heading above `offset` (or the start, after frontmatter)
    /// up to `offset`. With no heading above, the whole page.
    private func section(before offset: Int) -> String {
        let start = index.bodyStart
        let blockHere = index.blockIndex(at: max(start, offset - 1))
        var headingStart: Int?
        if let blockHere {
            for position in stride(from: blockHere, through: 0, by: -1) {
                if case .heading = index.blocks[position].kind {
                    headingStart = index.sourceRange(of: position).lowerBound
                    break
                }
            }
        }
        guard let headingStart else { return text.substring(from: start) }
        return text.substring(with: NSRange(location: headingStart, length: max(0, offset - headingStart)))
    }

    /// The block before `offset`, with a run of list items taken together.
    private func previousBlock(before offset: Int) -> (range: NSRange, text: String)? {
        guard offset > 0, var position = index.blockIndex(at: offset - 1) else { return nil }
        while position >= 0, index.sourceRange(of: position).lowerBound >= offset { position -= 1 }
        guard position >= 0 else { return nil }
        var first = position
        if index.blocks[position].kind.isListItem {
            while first > 0, index.blocks[first - 1].kind.isListItem { first -= 1 }
        }
        let start = index.sourceRange(of: first).lowerBound
        let end = index.sourceRange(of: position).upperBound
        let range = NSRange(location: start, length: end - start)
        return (range, text.substring(with: range))
    }
}
