/// A parsed document that knows where each block sits in the text, kept current as the
/// text is edited.
///
/// Offsets are UTF-16 code units, the unit `NSString` and the text views use. An edit
/// re-parses only the blocks around it; the rest of the document keeps its blocks and ids.
public struct BlockIndex: Sendable {
    public private(set) var document: Document
    /// Where each block's source starts. `starts[i]` belongs to `document.blocks[i]`.
    public private(set) var starts: [Int]
    /// Total length of the text.
    public private(set) var length: Int

    public init(text: String, flavor: DocumentFlavor = .markdown) {
        document = Document(parsing: text, flavor: flavor)
        starts = []
        length = 0
        recomputeOffsets()
    }

    public var blocks: [Block] { document.blocks }

    /// Where the frontmatter and leading blank lines end and the first block begins.
    public var bodyStart: Int { starts.first ?? length }

    /// The range of the frontmatter's source (fences included), if there is any.
    public var frontmatterRange: Range<Int>? {
        document.frontmatter.map { 0..<$0.source.utf16.count }
    }

    /// The block's source, without its trailing line breaks.
    public func sourceRange(of index: Int) -> Range<Int> {
        starts[index]..<(starts[index] + document.blocks[index].source.utf16.count)
    }

    /// The block's source plus its trailing line breaks.
    public func fullRange(of index: Int) -> Range<Int> {
        starts[index]..<(index + 1 < starts.count ? starts[index + 1] : length)
    }

    /// The block whose source or trailing text contains `offset`. Offsets in the
    /// frontmatter or leading blank lines have none. The end of the text belongs to the
    /// last block.
    public func blockIndex(at offset: Int) -> Int? {
        guard let first = starts.first, offset >= first else { return nil }
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Indices of the blocks overlapping `range`.
    public func blockIndices(overlapping range: Range<Int>) -> Range<Int> {
        guard !starts.isEmpty else { return 0..<0 }
        let lower = blockIndex(at: range.lowerBound) ?? 0
        let upper = blockIndex(at: max(range.lowerBound, range.upperBound - 1)) ?? lower
        return lower..<(max(lower, upper) + 1)
    }

    /// Updates the index for an edit that replaced `range` (in the old text) with
    /// `replacementLength` UTF-16 units. `text` is the whole text after the edit.
    ///
    /// Returns the indices of the blocks that now cover the edit, which are the ones
    /// whose styling may have changed. A full re-parse returns every block.
    @discardableResult
    public mutating func replace(_ range: Range<Int>, replacementLength: Int, in text: String) -> Range<Int> {
        let delta = replacementLength - range.count
        if let local = reparseLocally(range, delta: delta, text: text) { return local }
        document = Document(parsing: text, flavor: document.flavor)
        recomputeOffsets()
        return 0..<document.blocks.count
    }

    /// Re-parses the blocks around an edit. Returns nil when the edit could reach further
    /// (it touches the frontmatter, or it changed how the following block parses, as an
    /// opened code fence would), so the caller falls back to a full parse.
    private mutating func reparseLocally(_ range: Range<Int>, delta: Int, text: String) -> Range<Int>? {
        guard !starts.isEmpty, range.lowerBound >= bodyStart else { return nil }
        let count = starts.count
        let (first, last) = region(around: range)
        let sentinel = last + 1 < count ? last + 1 : nil
        let regionStart = starts[first]
        let oldRegionEnd = sentinel.map { fullRange(of: $0).upperBound } ?? length
        guard let regionText = Self.substring(of: text, regionStart..<(oldRegionEnd + delta)) else { return nil }

        // JSX regions can span blocks in ways a local parse can't see; parse MDX around
        // them in full.
        if document.flavor == .mdx, regionText.contains("<") || regionText.contains("{") { return nil }

        let reparsed = MarkdownParser.parse(regionText, flavor: document.flavor, detectFrontmatter: false)
        var replacement = reparsed.blocks
        guard reparsed.leading.isEmpty || first == 0 else { return nil }
        if let sentinel {
            // The block after the edit must come back exactly as it was.
            let old = document.blocks[sentinel]
            guard let new = replacement.last, new.source == old.source, new.trailing == old.trailing,
                new.kind == old.kind
            else { return nil }
            replacement[replacement.count - 1] = old
        }
        let oldBlocks = document.blocks[first...(sentinel ?? last)]
        // Keep ids for blocks that didn't change, so views keyed by id stay put.
        for (position, old) in zip(replacement.indices, oldBlocks) where replacement[position].source == old.source {
            replacement[position] = Block(
                id: old.id, kind: replacement[position].kind, source: old.source,
                trailing: replacement[position].trailing)
        }
        if first == 0 { document.leading += reparsed.leading }

        let oldUpper = (sentinel ?? last) + 1
        document.blocks.replaceSubrange(first..<oldUpper, with: replacement)

        var offset = regionStart + reparsed.leading.utf16.count
        var newStarts: [Int] = []
        newStarts.reserveCapacity(replacement.count)
        for block in replacement {
            newStarts.append(offset)
            offset += block.source.utf16.count + block.trailing.utf16.count
        }
        let tail = starts[oldUpper...].map { $0 + delta }
        starts.replaceSubrange(first..<count, with: newStarts + tail)
        length += delta
        let changedUpper = first + replacement.count - (sentinel == nil ? 0 : 1)
        return first..<max(first, changedUpper)
    }

    /// The blocks to re-parse for an edit: one block of context on each side, widened to
    /// whole runs of list items, since nested items only parse as list items alongside
    /// their parents.
    private func region(around range: Range<Int>) -> (first: Int, last: Int) {
        let count = starts.count
        let firstTouched = blockIndex(at: range.lowerBound) ?? 0
        let lastTouched = blockIndex(at: max(range.lowerBound, range.upperBound - 1)) ?? firstTouched
        var first = max(0, firstTouched - 1)
        var last = min(count - 1, lastTouched + 1)
        let blocks = document.blocks
        while first > 0, blocks[first].kind.isListItem, blocks[first - 1].kind.isListItem { first -= 1 }
        while last + 1 < count, blocks[last].kind.isListItem, blocks[last + 1].kind.isListItem { last += 1 }
        return (first, last)
    }

    private static func substring(of text: String, _ range: Range<Int>) -> String? {
        let utf16 = text.utf16
        guard range.lowerBound >= 0, range.upperBound <= utf16.count,
            let lower = utf16.index(utf16.startIndex, offsetBy: range.lowerBound, limitedBy: utf16.endIndex),
            let upper = utf16.index(utf16.startIndex, offsetBy: range.upperBound, limitedBy: utf16.endIndex)
        else { return nil }
        return String(utf16[lower..<upper])
    }

    private mutating func recomputeOffsets() {
        var offset = 0
        if let frontmatter = document.frontmatter {
            offset += frontmatter.source.utf16.count + frontmatter.trailing.utf16.count
        }
        offset += document.leading.utf16.count
        starts = []
        starts.reserveCapacity(document.blocks.count)
        for block in document.blocks {
            starts.append(offset)
            offset += block.source.utf16.count + block.trailing.utf16.count
        }
        length = offset
    }
}
