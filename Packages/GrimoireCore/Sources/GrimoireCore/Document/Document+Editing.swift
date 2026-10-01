import Foundation

/// Block-level edits. Each one rewrites only the blocks it touches and the line breaks
/// around them, so the rest of the file stays byte-identical.
extension Document {
    /// Inserts a new block of `kind` holding `text`, and returns its id.
    @discardableResult
    public mutating func insert(_ kind: BlockKind, text: String = "", at index: Int) -> Block.ID {
        let source = BlockText.render(
            text, as: kind, listIndent: listIndent(for: kind, before: index), lineEnding: lineEnding)
        let block = Block(kind: kind, source: source)
        insert(block, at: index)
        return block.id
    }

    public mutating func insert(_ block: Block, at index: Int) {
        var block = block
        let isLast = index == blocks.count
        if isLast {
            // The new last block inherits how the file ended.
            block.trailing = blocks.last?.trailing ?? lineEnding
            if !blocks.isEmpty { blocks[blocks.count - 1].trailing = "" }
        }
        blocks.insert(block, at: index)
        fixSeparator(after: index - 1)
        fixSeparator(after: index)
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Block {
        let removed = blocks.remove(at: index)
        if index == blocks.count, index > 0 {
            blocks[index - 1].trailing = removed.trailing
        }
        fixSeparator(after: index - 1)
        return removed
    }

    /// Moves the block at `source` so it ends up at index `destination`.
    public mutating func move(from source: Int, to destination: Int) {
        guard source != destination else { return }
        let block = remove(at: source)
        insert(block, at: destination)
    }

    /// Re-casts a block as another kind, keeping its text.
    public mutating func convert(at index: Int, to kind: BlockKind) {
        let text = blocks[index].text
        blocks[index].kind = kind
        blocks[index].source = BlockText.render(
            text, as: kind, listIndent: listIndent(for: kind, before: index), lineEnding: lineEnding)
        fixSeparator(after: index - 1)
        fixSeparator(after: index)
    }

    /// Replaces a block's text, keeping its kind.
    public mutating func setText(_ text: String, at index: Int) {
        let kind = blocks[index].kind
        blocks[index].source = BlockText.render(
            text, as: kind, listIndent: currentListIndent(at: index), lineEnding: lineEnding)
    }

    /// Replaces a block's raw markdown and re-parses only that block (or, for a list
    /// item, the run of list items around it). The edit can split one block into
    /// several or change its kind. Returns the range of blocks that now cover the edit.
    @discardableResult
    public mutating func replaceSource(at index: Int, with source: String) -> Range<Int> {
        blocks[index].source = source
        var lower = index
        var upper = index + 1
        if blocks[index].kind.isListItem {
            while lower > 0, blocks[lower - 1].kind.isListItem { lower -= 1 }
            while upper < blocks.count, blocks[upper].kind.isListItem { upper += 1 }
        }
        let original = Array(blocks[lower..<upper])
        let text = original.map { $0.source + $0.trailing }.joined()
        let reparsed = MarkdownParser.parse(text, flavor: flavor, detectFrontmatter: false)

        var replacement = reparsed.blocks
        for position in replacement.indices where position < original.count {
            let old = replacement[position]
            replacement[position] = Block(
                id: original[position].id, kind: old.kind, source: old.source, trailing: old.trailing)
        }
        if !reparsed.leading.isEmpty {
            if lower > 0 {
                blocks[lower - 1].trailing += reparsed.leading
            } else {
                leading += reparsed.leading
            }
        }
        blocks.replaceSubrange(lower..<upper, with: replacement)
        return lower..<(lower + replacement.count)
    }

    // MARK: - Separators

    /// Makes sure the break between block `index` and the next one keeps them apart:
    /// a blank line between most blocks, a single line break between list items.
    private mutating func fixSeparator(after index: Int) {
        guard index >= 0, index < blocks.count else { return }
        // The last block's trailing text is how the file ends; leave it alone.
        guard index + 1 < blocks.count else { return }
        let needsBlankLine = !(blocks[index].kind.isListItem && blocks[index + 1].kind.isListItem)
        let required = needsBlankLine ? 2 : 1
        if lineBreakCount(blocks[index].trailing) < required {
            blocks[index].trailing = String(repeating: lineEnding, count: required)
        }
    }

    private func lineBreakCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isNewline ? 1 : 0) }
    }

    // MARK: - List indentation

    /// Indentation for a new list item at `index` so it nests under the nearest
    /// preceding item one level up.
    private func listIndent(for kind: BlockKind, before index: Int) -> String {
        guard case .listItem(let item) = kind, item.indent > 0 else { return "" }
        for candidate in blocks[..<min(index, blocks.count)].reversed() {
            guard case .listItem(let parent) = candidate.kind else { break }
            if parent.indent == item.indent - 1 {
                return String(repeating: " ", count: Self.contentColumn(of: candidate.source))
            }
        }
        return String(repeating: "  ", count: item.indent)
    }

    private func currentListIndent(at index: Int) -> String {
        String(blocks[index].source.prefix { $0 == " " || $0 == "\t" })
    }

    /// Column where a list item's text starts: indent, marker and the spaces after it.
    private static func contentColumn(of source: String) -> Int {
        let line = source.prefix { !$0.isNewline }
        var column = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(column)
        let marker = rest.first.map { "-*+".contains($0) } == true ? 1 : rest.prefix { $0.isNumber }.count + 1
        column += marker
        column += line.dropFirst(column).prefix { $0 == " " }.count
        return column
    }
}
