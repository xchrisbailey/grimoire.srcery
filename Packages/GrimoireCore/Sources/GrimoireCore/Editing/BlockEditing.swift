import Foundation

/// The editor's block behaviors (Notion-style keys, list handling, moving blocks) as
/// plain text edits, so the file stays ordinary markdown.
///
/// Each function looks at the text, its `BlockIndex` and the selection, and returns the
/// edit to make, or nil when the key should do what it normally does.
public struct BlockEditing {
    public let text: String
    public let index: BlockIndex
    public let selection: Range<Int>

    private let nsText: NSString

    public init(text: String, index: BlockIndex, selection: Range<Int>) {
        self.text = text
        self.index = index
        self.selection = selection
        nsText = text as NSString
    }

    var caret: Int { selection.lowerBound }

    // MARK: - Lines

    /// The caret's line, without its line break.
    func line(at offset: Int) -> NSRange {
        var start = 0
        var contentsEnd = 0
        nsText.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    func string(_ range: NSRange) -> String { nsText.substring(with: range) }

    /// The block holding `offset`, when the offset is in its source rather than the blank
    /// lines after it.
    func block(at offset: Int) -> Int? {
        guard let position = index.blockIndex(at: offset) else { return nil }
        let source = index.sourceRange(of: position)
        return offset <= source.upperBound ? position : nil
    }

    // MARK: - Enter

    /// Enter starts a new block: it continues lists, quotes and tasks, leaves a list from
    /// an empty item, and keeps indentation inside code. With `soft`, it breaks the line
    /// inside the current block instead.
    public func newline(soft: Bool = false) -> TextEdit? {
        guard selection.isEmpty, let position = block(at: caret) else { return nil }
        let line = line(at: caret)
        let lineText = string(line)
        switch index.blocks[position].kind {
        case .listItem:
            return listNewline(position: position, line: line, soft: soft)
        case .blockquote:
            let marker = MarkdownSyntax.quoteMarker(in: lineText)
            if !soft, marker > 0, lineText.utf16.count == marker {
                return replace(NSRange(location: line.location, length: marker), with: "", caretAt: line.location)
            }
            return insert("\n" + (marker > 0 ? "> " : ""))
        case .codeBlock:
            let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
            return insert("\n" + indent)
        case .heading:
            return soft ? nil : insert("\n\n")
        case .paragraph:
            if soft { return insert("\n") }
            return lineText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : insert("\n\n")
        default:
            return nil
        }
    }

    private func listNewline(position: Int, line: NSRange, soft: Bool) -> TextEdit? {
        let firstLine = self.line(at: index.sourceRange(of: position).lowerBound)
        let prefix = MarkdownSyntax.listPrefix(in: string(firstLine))
        if soft {
            return insert("\n" + String(repeating: " ", count: prefix.indent + prefix.marker))
        }
        guard firstLine.location == line.location else {
            // An empty nested marker can't start a list under a paragraph, so markdown reads
            // it as part of the item above. Enter on it steps back out to that item's level.
            let lineText = string(line)
            let own = MarkdownSyntax.listPrefix(in: lineText)
            if own.marker > 0, lineText.utf16.count == own.length,
                lineText.trimmingCharacters(in: .whitespaces).first.map({ "-*+0123456789".contains($0) }) == true
            {
                let replacement = nextPrefix(after: string(firstLine), prefix: prefix)
                return replace(line, with: replacement, caretAt: line.location + replacement.utf16.count)
            }
            // A continuation line: start a fresh item at the same level.
            return insert("\n" + nextPrefix(after: string(firstLine), prefix: prefix))
        }
        let content = string(NSRange(location: line.location + prefix.length, length: line.length - prefix.length))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Enter on an empty item leaves the list, or steps out one level when nested.
            if prefix.indent > 0, let outdent = indent(outdent: true) { return outdent }
            return replace(NSRange(location: line.location, length: line.length), with: "", caretAt: line.location)
        }
        guard caret >= line.location + prefix.length else { return insert("\n") }
        return insert("\n" + nextPrefix(after: string(line), prefix: prefix))
    }

    /// The marker for the item after `line`: same indent and bullet, the next number, and an
    /// unchecked box when the line is a task.
    private func nextPrefix(after line: String, prefix: MarkdownSyntax.ListPrefix) -> String {
        let units = Array(line.utf16)
        let indent = String(decoding: units[0..<prefix.indent], as: UTF16.self)
        let marker = String(decoding: units[prefix.indent..<(prefix.indent + prefix.marker)], as: UTF16.self)
            .trimmingCharacters(in: .whitespaces)
        var next = marker
        if let delimiter = marker.last, delimiter == "." || delimiter == ")", let number = Int(marker.dropLast()) {
            next = "\(number + 1)\(delimiter)"
        }
        return indent + next + " " + (prefix.checkbox > 0 ? "[ ] " : "")
    }

    // MARK: - Backspace

    /// Backspace at the start of a block's text first turns it into a paragraph, then merges
    /// it into the block before.
    public func backspace() -> TextEdit? {
        guard selection.isEmpty, let position = block(at: caret) else { return nil }
        let source = index.sourceRange(of: position)
        let line = line(at: caret)
        let isFirstLine = line.location == source.lowerBound
        let lineText = string(line)
        switch index.blocks[position].kind {
        case .listItem:
            guard isFirstLine else { return nil }
            // Following another item, the text needs a blank line or it joins that item.
            let follows = position > 0 && index.blocks[position - 1].kind.isListItem
            return removeMarker(MarkdownSyntax.listPrefix(in: lineText).length, on: line, leaving: follows ? "\n" : "")
        case .blockquote:
            return removeMarker(MarkdownSyntax.quoteMarker(in: lineText), on: line)
        case .heading:
            guard isFirstLine else { return nil }
            return removeMarker(MarkdownSyntax.headingMarkers(in: lineText).prefix, on: line)
        case .paragraph:
            return mergeWithPrevious(position)
        default:
            return nil
        }
    }

    /// Removes a line's `length`-long marker when the caret sits right after it.
    private func removeMarker(_ length: Int, on line: NSRange, leaving replacement: String = "") -> TextEdit? {
        guard length > 0, caret == line.location + length else { return nil }
        return replace(
            NSRange(location: line.location, length: length), with: replacement,
            caretAt: line.location + replacement.utf16.count)
    }

    /// Joins a paragraph to the text block before it, when the caret is at its start.
    private func mergeWithPrevious(_ position: Int) -> TextEdit? {
        guard caret == index.sourceRange(of: position).lowerBound, position > 0 else { return nil }
        switch index.blocks[position - 1].kind {
        case .paragraph, .heading, .listItem, .blockquote:
            let end = index.sourceRange(of: position - 1).upperBound
            return replace(NSRange(location: end, length: caret - end), with: "", caretAt: end)
        default:
            return nil
        }
    }

    // MARK: - Indent

    /// Tab and Shift-Tab on a list item nest it under the item before, or move it out one
    /// level. Every line of the item moves, so wrapped text stays with it. Returns nil
    /// outside lists.
    public func indent(outdent: Bool) -> TextEdit? {
        guard let position = block(at: caret), case .listItem = index.blocks[position].kind else { return nil }
        let source = NSRange(index.sourceRange(of: position))
        let first = line(at: source.location)
        let prefix = MarkdownSyntax.listPrefix(in: string(first))
        let shift: Int
        if outdent {
            guard prefix.indent > 0 else { return .none(keeping: selection) }
            let parent = (0..<position).reversed().lazy
                .prefix { index.blocks[$0].kind.isListItem }
                .map { MarkdownSyntax.listPrefix(in: string(line(at: index.sourceRange(of: $0).lowerBound))) }
                .first { $0.indent < prefix.indent }
            shift = -(prefix.indent - (parent?.indent ?? 0))
        } else {
            guard position > 0, index.blocks[position - 1].kind.isListItem else { return .none(keeping: selection) }
            let previous = MarkdownSyntax.listPrefix(
                in: string(line(at: index.sourceRange(of: position - 1).lowerBound)))
            // Nest under the previous item's text, or one level deeper than it if it's
            // already nested further.
            let target = previous.indent >= prefix.indent ? previous.indent + previous.marker : prefix.indent
            guard target > prefix.indent else { return .none(keeping: selection) }
            shift = target - prefix.indent
        }
        return shiftLines(in: source, by: shift)
    }

    /// Adds `shift` spaces to (or removes them from) the start of every line in `range`.
    private func shiftLines(in range: NSRange, by shift: Int) -> TextEdit {
        let block = string(range)
        var lines: [String] = []
        block.enumerateLines { line, _ in lines.append(line) }
        if block.hasSuffix("\n") { lines.append("") }
        let shifted = lines.map { line -> String in
            if shift > 0 { return line.isEmpty ? line : String(repeating: " ", count: shift) + line }
            let spaces = min(-shift, line.prefix { $0 == " " }.count)
            return String(line.dropFirst(spaces))
        }
        let replacement = shifted.joined(separator: "\n")
        let firstShift = shift > 0 ? shift : -min(-shift, lines.first?.prefix { $0 == " " }.count ?? 0)
        let moved = { (offset: Int) in max(range.location, offset + firstShift) }
        return TextEdit(
            range: range.location..<NSMaxRange(range), replacement: replacement,
            selection: moved(selection.lowerBound)..<moved(selection.upperBound))
    }

    // MARK: - Markdown shortcuts

    /// Expands shortcuts that plain markdown doesn't already cover, just after a character
    /// was typed: `[] ` becomes a task, and a third backtick opens a code block with its
    /// closing fence. (`# `, `- `, `1. `, `> ` and `---` are markdown already.)
    public func shortcut() -> TextEdit? {
        guard selection.isEmpty else { return nil }
        let line = line(at: caret)
        guard caret == NSMaxRange(line) else { return nil }
        let lineText = string(line)
        let leading = lineText.prefix { $0 == " " }
        let rest = lineText.dropFirst(leading.count)
        if rest == "[] " || rest == "[ ] " {
            let replacement = leading + "- [ ] "
            return replace(line, with: String(replacement), caretAt: line.location + replacement.utf16.count)
        }
        if rest == "```" || rest == "~~~", let position = block(at: caret),
            case .codeBlock = index.blocks[position].kind,
            index.sourceRange(of: position).lowerBound == line.location,
            // An unclosed fence runs to the end of the text, so it's the last block.
            position == index.blocks.count - 1
        {
            return TextEdit(range: caret..<caret, replacement: "\n" + leading + rest, selection: caret..<caret)
        }
        return nil
    }

    // MARK: - Tasks

    /// Checks or unchecks the task holding the caret.
    public func toggleTask() -> TextEdit? {
        guard let position = block(at: caret), case .listItem(let item) = index.blocks[position].kind,
            item.checkbox != nil
        else { return nil }
        let first = line(at: index.sourceRange(of: position).lowerBound)
        return Self.toggleTask(onLine: first, in: nsText, selection: selection)
    }

    /// Flips the checkbox on the task line at `line`.
    public static func toggleTask(onLine line: NSRange, in text: NSString, selection: Range<Int>) -> TextEdit? {
        let prefix = MarkdownSyntax.listPrefix(in: text.substring(with: line))
        guard prefix.checkbox > 0 else { return nil }
        let box = line.location + prefix.indent + prefix.marker + 1
        let checked = text.substring(with: NSRange(location: box, length: 1)) != " "
        return TextEdit(range: box..<(box + 1), replacement: checked ? " " : "x", selection: selection)
    }

    // MARK: - Helpers

    func insert(_ string: String) -> TextEdit {
        let end = caret + string.utf16.count
        return TextEdit(range: selection, replacement: string, selection: end..<end)
    }

    func replace(_ range: NSRange, with replacement: String, caretAt caret: Int) -> TextEdit {
        TextEdit(range: range.location..<NSMaxRange(range), replacement: replacement, selection: caret..<caret)
    }
}
