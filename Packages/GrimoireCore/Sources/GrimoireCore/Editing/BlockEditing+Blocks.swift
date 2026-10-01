import Foundation

/// Whole-block commands: move, duplicate, delete, turn into, select.
extension BlockEditing {
    /// The block holding the caret (or the start of the selection).
    public var currentBlock: Int? {
        index.blockIndex(at: caret)
    }

    /// Selects the whole source of the caret's block.
    public func blockSelection() -> Range<Int>? {
        currentBlock.map { index.sourceRange(of: $0) }
    }

    /// Swaps the caret's block with the one above or below. The caret moves with it.
    public func moveBlock(upward: Bool) -> TextEdit? {
        guard let position = currentBlock else { return .none(keeping: selection) }
        let target = upward ? position - 1 : position + 1
        guard index.blocks.indices.contains(target) else { return .none(keeping: selection) }
        return moveBlock(position, to: target)
    }

    /// Moves block `source` so it ends up at index `destination`, keeping the caret inside it
    /// when it was there.
    public func moveBlock(_ source: Int, to destination: Int) -> TextEdit? {
        guard source != destination, index.blocks.indices.contains(source), index.blocks.indices.contains(destination)
        else { return nil }
        var document = index.document
        document.move(from: source, to: destination)
        let offsetInBlock = caret - index.sourceRange(of: source).lowerBound
        let movedStart = Self.start(of: destination, in: document)
        let inside = index.sourceRange(of: source).contains(caret) || caret == index.sourceRange(of: source).upperBound
        let newCaret = inside ? movedStart + offsetInBlock : movedStart
        return edit(to: document, caret: newCaret)
    }

    /// Puts a copy of the caret's block right after it and moves the caret into the copy.
    public func duplicateBlock() -> TextEdit? {
        guard let position = currentBlock else { return nil }
        var document = index.document
        let original = document.blocks[position]
        document.insert(Block(kind: original.kind, source: original.source), at: position + 1)
        let offsetInBlock = max(0, caret - index.sourceRange(of: position).lowerBound)
        return edit(to: document, caret: Self.start(of: position + 1, in: document) + offsetInBlock)
    }

    /// Removes block `position` and the space after it.
    public func deleteBlock(_ position: Int? = nil) -> TextEdit? {
        guard let position = position ?? currentBlock, index.blocks.indices.contains(position) else { return nil }
        var document = index.document
        document.remove(at: position)
        let caret =
            document.blocks.isEmpty ? 0 : Self.start(of: min(position, document.blocks.count - 1), in: document)
        return edit(to: document, caret: caret)
    }

    /// Re-casts block `position` (the caret's by default) as `kind`, keeping its text.
    public func convert(_ position: Int? = nil, to kind: BlockKind) -> TextEdit? {
        guard let position = position ?? currentBlock, index.blocks.indices.contains(position) else { return nil }
        var document = index.document
        document.convert(at: position, to: kind)
        let start = Self.start(of: position, in: document)
        // Keep the caret at the same spot in the text, after whatever marker the block has now.
        let oldBlock = index.blocks[position]
        let oldOffset = caret - index.sourceRange(of: position).lowerBound
        let oldPrefix = oldBlock.source.utf16.count - oldBlock.text.utf16.count
        let newBlock = document.blocks[position]
        let newPrefix = newBlock.source.utf16.count - newBlock.text.utf16.count
        let textOffset = max(0, oldOffset - max(0, oldPrefix))
        let newCaret = min(start + newBlock.source.utf16.count, start + max(0, newPrefix) + textOffset)
        return edit(to: document, caret: newCaret)
    }

    // MARK: - Helpers

    private func edit(to document: Document, caret: Int) -> TextEdit {
        TextEdit.difference(from: text, to: document.markdown, selection: caret..<caret)
    }

    /// Where block `position` starts in `document`'s markdown.
    static func start(of position: Int, in document: Document) -> Int {
        var offset = document.leading.utf16.count
        if let frontmatter = document.frontmatter {
            offset += frontmatter.source.utf16.count + frontmatter.trailing.utf16.count
        }
        for block in document.blocks.prefix(position) {
            offset += block.source.utf16.count + block.trailing.utf16.count
        }
        return offset
    }
}
