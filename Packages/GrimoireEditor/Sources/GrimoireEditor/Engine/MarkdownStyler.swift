import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns markdown source into styled text without changing a character: headings sized,
/// emphasis and code styled, markers dimmed on the caret's block and hidden elsewhere,
/// and decorations attached for the layout fragments to draw.
@MainActor
public final class MarkdownStyler {
    public var theme: EditorTheme
    /// The document's folder, for resolving relative image paths.
    public var baseURL: URL?
    public var images: ImageCache
    /// Called when an image preview finishes loading, so its block can be restyled.
    public var onImageLoaded: ((URL) -> Void)?

    public init(theme: EditorTheme = EditorTheme(), images: ImageCache = .shared) {
        self.theme = theme
        self.images = images
    }

    /// Styles the whole text.
    public func styleAll(_ storage: NSMutableAttributedString, index: BlockIndex, revealing revealed: Int?) {
        style(storage, index: index, blocks: 0..<index.blocks.count, revealing: revealed)
        if index.blocks.isEmpty { styleFront(storage, index: index) }
    }

    /// Styles the blocks in `blocks`. `revealed` is the block holding the caret, whose
    /// markers stay visible.
    public func style(
        _ storage: NSMutableAttributedString, index: BlockIndex, blocks: Range<Int>, revealing revealed: Int?
    ) {
        if blocks.lowerBound == 0 { styleFront(storage, index: index) }
        for position in blocks where position < index.blocks.count {
            styleBlock(position, in: storage, index: index, reveal: position == revealed)
        }
    }

    // MARK: - Attributes

    func paragraphStyle(
        firstLineIndent: CGFloat = 0, indent: CGFloat = 0, tailIndent: CGFloat = 0, lineHeight: CGFloat? = nil,
        spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight ?? theme.lineHeightMultiple
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = indent
        style.tailIndent = tailIndent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.body, .foregroundColor: theme.ink, .paragraphStyle: paragraphStyle()]
    }

    /// Dims markdown syntax on the caret's block and hides it everywhere else.
    func applyMarker(_ range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        guard range.length > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] =
            reveal
            ? [.foregroundColor: theme.marker, .grimoireMarker: true]
            : [.font: EditorTheme.hiddenFont, .foregroundColor: PlatformColor.clear, .grimoireMarker: true]
        storage.addAttributes(attributes, range: range)
    }

    // MARK: - Front matter

    private func styleFront(_ storage: NSMutableAttributedString, index: BlockIndex) {
        let range = NSRange(location: 0, length: min(index.bodyStart, storage.length))
        guard range.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: range)
        if let frontmatter = index.frontmatterRange {
            storage.addAttributes(
                [.font: theme.metadata, .foregroundColor: theme.faint],
                range: NSRange(location: 0, length: frontmatter.count))
        }
    }

    // MARK: - Blocks

    private func styleBlock(_ position: Int, in storage: NSMutableAttributedString, index: BlockIndex, reveal: Bool) {
        let block = index.blocks[position]
        let fullRange = NSRange(index.fullRange(of: position))
        let range = NSRange(index.sourceRange(of: position))
        guard NSMaxRange(fullRange) <= storage.length else { return }
        storage.setAttributes(baseAttributes, range: fullRange)

        switch block.kind {
        case .paragraph:
            styleInline(range, in: storage, baseFont: theme.body, reveal: reveal)
        case .heading(let level):
            styleHeading(level: level, range: range, in: storage, reveal: reveal)
        case .listItem(let item):
            styleListItem(item, range: range, in: storage, reveal: reveal)
        case .blockquote:
            styleQuote(range, in: storage, reveal: reveal)
        case .codeBlock:
            let source = (storage.string as NSString).substring(with: range)
            styleCode(range, in: storage, fenced: MarkdownSyntax.isFenced(source))
        case .thematicBreak:
            storage.addAttribute(.grimoireDecoration, value: LineDecoration(.rule), range: range)
            applyMarker(range, in: storage, reveal: reveal)
        case .image:
            styleImage(range, in: storage, reveal: reveal)
        case .table, .html, .mdx, .linkDefinitions:
            styleSource(block.kind, range: range, in: storage)
        }
    }

    /// Blocks shown as their source: tables (until #22), HTML, MDX and link definitions.
    private func styleSource(_ kind: BlockKind, range: NSRange, in storage: NSMutableAttributedString) {
        switch kind {
        case .table:
            let font = theme.font(size: theme.codeSize, monospaced: true)
            storage.addAttributes([.font: font, .paragraphStyle: paragraphStyle(lineHeight: 1.15)], range: range)
            styleInline(range, in: storage, baseFont: font, reveal: true)
            dimCharacters("|", in: range, of: storage)
        case .mdx:
            storage.addAttributes([.font: theme.code, .foregroundColor: theme.sparkle], range: range)
        case .linkDefinitions:
            storage.addAttributes([.font: theme.metadata, .foregroundColor: theme.faint], range: range)
        default:
            storage.addAttributes([.font: theme.code, .foregroundColor: theme.subtext], range: range)
        }
    }

    // MARK: - Helpers

    func forEachLine(of range: NSRange, in text: NSString, _ body: (NSRange) -> Void) {
        var location = range.location
        let end = NSMaxRange(range)
        repeat {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineContentEnd = min(contentsEnd, end)
            body(NSRange(location: location, length: max(0, lineContentEnd - location)))
            if lineEnd <= location { break }
            location = lineEnd
        } while location < end
    }

    private func dimCharacters(_ character: Character, in range: NSRange, of storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        guard let target = String(character).utf16.first else { return }
        for offset in 0..<range.length where text.character(at: range.location + offset) == target {
            storage.addAttribute(
                .foregroundColor, value: theme.marker, range: NSRange(location: range.location + offset, length: 1))
        }
    }
}

extension NSRange {
    init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }
}
