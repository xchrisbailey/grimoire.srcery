import Foundation
import GrimoireCore

/// Works out the markdown a spell writes. It removes the typed `/query`, then edits the
/// caret's line or puts a new block there.
public struct SpellCaster {
    /// What the editor still has to do after the text changes.
    public enum FollowUp: Equatable, Sendable {
        case none
        /// Offer languages; the chosen one goes at `fenceEnd`, then the caret moves to `codeLine`.
        case pickLanguage(fenceEnd: Int, codeLine: Int)
        /// Ask for an image file and insert it at `offset`.
        case pickImage(offset: Int)
    }

    public struct Result: Equatable, Sendable {
        public var edit: TextEdit
        public var followUp: FollowUp
    }

    public let text: String
    /// The `/` and whatever was typed after it.
    public let trigger: Range<Int>
    public var today = Date()

    public init(text: String, trigger: Range<Int>) {
        self.text = text
        self.trigger = trigger
    }

    public func cast(_ spell: Spell) -> Result {
        let base = (text as NSString).replacingCharacters(in: NSRange(trigger), with: "") as NSString
        let caret = trigger.lowerBound
        var draft = Draft(text: base, caret: caret)
        let followUp: FollowUp
        switch spell.effect {
        case .turnInto(let kind):
            draft.turnLine(into: kind)
            followUp = .none
        case .codeBlock:
            followUp = draft.codeBlock()
        case .table:
            draft.insertBlock("| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |", caretAt: 40)
            followUp = .none
        case .divider:
            draft.insertBlock("---\n\n", caretAt: 5)
            followUp = .none
        case .image:
            followUp = .pickImage(offset: caret)
        case .link:
            draft.insert("[]()", caretAt: 1)
            followUp = .none
        case .callout:
            draft.turnLine(into: .paragraph)
            draft.prefixLine(with: "> [!NOTE]\n> ")
            followUp = .none
        case .date:
            draft.insert(Self.isoDate(today), caretAt: nil)
            followUp = .none
        case .frontmatter:
            draft.frontmatter()
            followUp = .none
        case .intelligence:
            // The editor hands these to the app instead of casting them here.
            followUp = .none
        }
        let edit = TextEdit.difference(from: text, to: draft.text as String, selection: draft.caret..<draft.caret)
        return Result(edit: edit, followUp: followUp)
    }

    static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// The text being rewritten by a spell, with its caret.
private struct Draft {
    var text: NSString
    var caret: Int

    var line: NSRange {
        var start = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    mutating func replace(_ range: NSRange, with string: String, caret newCaret: Int) {
        text = text.replacingCharacters(in: range, with: string) as NSString
        caret = newCaret
    }

    mutating func insert(_ string: String, caretAt offset: Int?) {
        let length = string.utf16.count
        replace(NSRange(location: caret, length: 0), with: string, caret: caret + (offset ?? length))
    }

    /// The length of whatever block marker starts `line`: list, task, heading or quote.
    func markerLength(of line: String) -> Int {
        let trimmed = line.drop { $0 == " " }
        if trimmed.hasPrefix("#") { return MarkdownSyntax.headingMarkers(in: line).prefix }
        if trimmed.hasPrefix(">") { return MarkdownSyntax.quoteMarker(in: line) }
        if let first = trimmed.first, "-*+".contains(first) || first.isNumber {
            let prefix = MarkdownSyntax.listPrefix(in: line)
            // "-text" or "12" isn't a list marker: it needs the space after it.
            let lastOfMarker = Array(line.utf16)[prefix.indent + prefix.marker - 1]
            if prefix.marker > 1, lastOfMarker == UInt16(UInt8(ascii: " ")) { return prefix.length }
        }
        return 0
    }

    mutating func turnLine(into kind: BlockKind) {
        let line = line
        let lineText = text.substring(with: line)
        let oldMarker = markerLength(of: lineText)
        let content = (lineText as NSString).substring(from: oldMarker)
        let marker: String
        switch kind {
        case .heading(let level): marker = String(repeating: "#", count: level) + " "
        case .listItem(let item) where item.checkbox != nil: marker = "- [ ] "
        case .listItem(let item):
            if case .ordered(let number) = item.marker { marker = "\(number). " } else { marker = "- " }
        case .blockquote: marker = "> "
        default: marker = ""
        }
        let offset = max(0, caret - line.location - oldMarker)
        replace(line, with: marker + content, caret: line.location + marker.utf16.count + offset)
    }

    mutating func prefixLine(with prefix: String) {
        let line = line
        let offset = caret - line.location
        replace(
            NSRange(location: line.location, length: 0), with: prefix,
            caret: line.location + prefix.utf16.count + offset)
    }

    /// Wraps the line in a fence, leaving the caret where the language goes.
    mutating func codeBlock() -> SpellCaster.FollowUp {
        let line = line
        let content = text.substring(with: line).trimmingCharacters(in: .whitespaces)
        insertBlock("```\n" + content + "\n```", caretAt: 3)
        return .pickLanguage(fenceEnd: caret, codeLine: caret + 1 + content.utf16.count)
    }

    /// Puts `block` in place of an empty line, or after the line when it has text, with blank
    /// lines around it so it parses on its own.
    mutating func insertBlock(_ block: String, caretAt offset: Int) {
        let line = line
        let isEmpty = text.substring(with: line).trimmingCharacters(in: .whitespaces).isEmpty
        if isEmpty {
            let before = line.location > 0 && !previousLineIsBlank(line) ? "\n" : ""
            let after = NSMaxRange(line) < text.length && !nextLineIsBlank(line) ? "\n" : ""
            let start = line.location + before.utf16.count
            replace(line, with: before + block + after, caret: start + offset)
        } else {
            let end = NSMaxRange(line)
            let after = end < text.length && !nextLineIsBlank(line) ? "\n" : ""
            replace(NSRange(location: end, length: 0), with: "\n\n" + block + after, caret: end + 2 + offset)
        }
    }

    private func previousLineIsBlank(_ line: NSRange) -> Bool {
        guard line.location > 0 else { return true }
        let previous = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
        return text.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func nextLineIsBlank(_ line: NSRange) -> Bool {
        let next = NSMaxRange(text.lineRange(for: line))
        guard next < text.length else { return true }
        return text.substring(with: text.lineRange(for: NSRange(location: next, length: 0)))
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Adds `title:` frontmatter at the top, or moves into the frontmatter already there.
    mutating func frontmatter() {
        let string = text as String
        if string.hasPrefix("---\n") || string.hasPrefix("---\r\n") {
            caret = string.hasPrefix("---\r\n") ? 5 : 4
            return
        }
        replace(NSRange(location: 0, length: 0), with: "---\ntitle: \n---\n\n", caret: 11)
    }
}
