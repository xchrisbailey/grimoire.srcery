import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// How the editor shows markdown.
public enum EditorMode: String, Codable, CaseIterable, Sendable {
    /// Styled in place: headings sized, markers hidden off the caret's block. Editable.
    case preview
    /// The exact source in Geist Mono with syntax colors.
    case raw
}

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
    /// Measured table cell widths, by a hash of the cell's text and fonts.
    var cellWidths: [Int: CGFloat] = [:]
    /// Where the caret is, for styling that reveals markers on just its line (table rows).
    public var caret: Int?
    /// Preview styles markdown in place; Raw shows the source with syntax colors.
    public var mode: EditorMode = .preview

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

    /// Shows markdown syntax quietly on the caret's block and hides it everywhere else.
    func applyMarker(
        _ range: NSRange, in storage: NSMutableAttributedString, reveal: Bool, token: MarkdownToken = .syntaxMarker
    ) {
        guard range.length > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] =
            reveal
            ? [.foregroundColor: theme.token(token, raw: false).color ?? theme.marker, .grimoireMarker: true]
            : [.font: EditorTheme.hiddenFont, .foregroundColor: PlatformColor.clear, .grimoireMarker: true]
        storage.addAttributes(attributes, range: range)
    }

    /// Adds a Preview token's color and decorations to `range`.
    func applyPreview(_ token: MarkdownToken, to range: NSRange, in storage: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        storage.addAttributes(theme.token(token, raw: false).attributes, range: range)
    }

    // MARK: - Front matter

    private func styleFront(_ storage: NSMutableAttributedString, index: BlockIndex) {
        let range = NSRange(location: 0, length: min(index.bodyStart, storage.length))
        guard range.length > 0 else { return }
        if mode == .raw { return styleRawFront(storage, index: index, range: range) }
        storage.setAttributes(baseAttributes, range: range)
        if let frontmatter = index.frontmatterRange {
            let range = NSRange(location: 0, length: frontmatter.count)
            storage.addAttributes([.font: theme.metadata, .foregroundColor: theme.faint], range: range)
            applyPreview(.frontmatter, to: range, in: storage)
        }
    }

    // MARK: - Blocks

    private func styleBlock(_ position: Int, in storage: NSMutableAttributedString, index: BlockIndex, reveal: Bool) {
        let block = index.blocks[position]
        let fullRange = NSRange(index.fullRange(of: position))
        let range = NSRange(index.sourceRange(of: position))
        guard NSMaxRange(fullRange) <= storage.length else { return }
        if mode == .raw { return styleRawBlock(block.kind, range: range, fullRange: fullRange, in: storage) }
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
            styleSource(block.kind, range: range, in: storage, reveal: reveal)
        }
    }

    /// Blocks shown as their source: HTML, MDX and link definitions (and tables that don't
    /// parse).
    private func styleSource(_ kind: BlockKind, range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        switch kind {
        case .table:
            styleTable(range, in: storage, reveal: reveal)
        case .mdx:
            styleMDX(range, in: storage, raw: false)
        case .linkDefinitions:
            storage.addAttributes([.font: theme.metadata, .foregroundColor: theme.faint], range: range)
        default:
            storage.addAttributes([.font: theme.code, .foregroundColor: theme.subtext], range: range)
            applyPreview(.html, to: range, in: storage)
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
}

extension NSRange {
    init(_ range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }
}
