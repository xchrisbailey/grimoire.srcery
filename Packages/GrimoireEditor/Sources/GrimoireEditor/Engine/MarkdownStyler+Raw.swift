import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Raw mode: every character in Geist Mono, markdown syntax colored by the theme's Raw
/// token styles (in Catppuccin: headings mauve, list and emphasis markers peach, quotes
/// teal, MDX pink) and nothing hidden or drawn.
extension MarkdownStyler {
    var rawFont: PlatformFont { theme.font(size: theme.codeSize, monospaced: true) }

    var rawAttributes: [NSAttributedString.Key: Any] {
        [
            .font: rawFont, .foregroundColor: theme.ink,
            .paragraphStyle: paragraphStyle(lineHeight: theme.rawLineHeightMultiple),
        ]
    }

    /// Applies a Raw token's color, decorations and weight to `range`.
    func applyRaw(_ token: MarkdownToken, to range: NSRange, in storage: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        let style = theme.token(token, raw: true)
        storage.addAttributes(style.attributes, range: range)
        if style.bold != nil || style.italic != nil {
            storage.addAttribute(
                .font,
                value: theme.font(
                    size: theme.codeSize, weight: style.bold == true ? 700 : 400, italic: style.italic == true,
                    monospaced: true),
                range: range)
        }
    }

    func styleRawFront(_ storage: NSMutableAttributedString, index: BlockIndex, range: NSRange) {
        storage.setAttributes(rawAttributes, range: range)
        guard let frontmatter = index.frontmatterRange else { return }
        let text = storage.string as NSString
        forEachLine(of: NSRange(frontmatter), in: text) { line in
            let content = text.substring(with: line)
            if content.trimmingCharacters(in: .whitespaces) == "---" {
                applyRaw(.frontmatter, to: line, in: storage)
            } else if let colon = content.firstIndex(of: ":") {
                let keyLength = content[..<colon].utf16.count
                applyRaw(.frontmatterKey, to: NSRange(location: line.location, length: keyLength), in: storage)
                applyRaw(
                    .frontmatterValue,
                    to: NSRange(location: line.location + keyLength + 1, length: line.length - keyLength - 1),
                    in: storage)
            }
        }
    }

    func styleRawBlock(_ kind: BlockKind, range: NSRange, fullRange: NSRange, in storage: NSMutableAttributedString) {
        storage.setAttributes(rawAttributes, range: fullRange)
        switch kind {
        case .heading(let level):
            applyRaw(.heading(level), to: range, in: storage)
        case .listItem:
            styleRawListItem(range, in: storage)
        case .blockquote:
            styleRawQuote(range, in: storage)
        case .codeBlock(let language):
            applyRaw(.codeBlock, to: range, in: storage)
            styleRawFences(range, in: storage)
            highlightCode(range, language: language, in: storage, raw: true)
        case .thematicBreak, .html, .linkDefinitions:
            let token: MarkdownToken = kind == .html ? .html : kind == .thematicBreak ? .syntaxMarker : .linkDestination
            applyRaw(token, to: range, in: storage)
        case .mdx:
            styleMDX(range, in: storage, raw: true)
        case .paragraph, .image, .table:
            styleRawInline(range, in: storage)
        }
    }

    private func styleRawListItem(_ range: NSRange, in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        let firstLine = NSIntersectionRange(text.lineRange(for: NSRange(location: range.location, length: 0)), range)
        let prefix = MarkdownSyntax.listPrefix(in: text.substring(with: firstLine))
        applyRaw(
            .listMarker,
            to: NSRange(location: range.location + prefix.indent, length: prefix.marker + prefix.checkbox),
            in: storage)
        styleRawInline(
            NSRange(location: range.location + prefix.length, length: range.length - prefix.length), in: storage)
    }

    private func styleRawQuote(_ range: NSRange, in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        storage.addAttribute(.foregroundColor, value: theme.subtext, range: range)
        forEachLine(of: range, in: text) { line in
            let content = text.substring(with: line)
            let marker = MarkdownSyntax.quoteMarker(in: content)
            applyRaw(.quote, to: NSRange(location: line.location, length: marker), in: storage)
            // A GitHub alert's `[!NOTE]` reads as part of the quote marker.
            let rest = (content as NSString).substring(from: marker)
            if rest.hasPrefix("[!"), let close = rest.firstIndex(of: "]") {
                let length = rest[...close].utf16.count
                applyRaw(.quote, to: NSRange(location: line.location + marker, length: length), in: storage)
            }
        }
    }

    /// Colors a fenced code block's fence lines.
    private func styleRawFences(_ range: NSRange, in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        guard MarkdownSyntax.isFenced(text.substring(with: range)) else { return }
        var lines: [NSRange] = []
        forEachLine(of: range, in: text) { lines.append($0) }
        if let first = lines.first { applyRaw(.codeFence, to: first, in: storage) }
        if lines.count > 1, let last = lines.last { applyRaw(.codeFence, to: last, in: storage) }
    }

    /// Colors inline syntax: emphasis markers, code, link text and destinations.
    func styleRawInline(_ range: NSRange, in storage: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        for span in InlineScanner.scan((storage.string as NSString).substring(with: range)) {
            let content = NSRange(location: range.location + span.content.lowerBound, length: span.content.count)
            let markerToken: MarkdownToken
            switch span.kind {
            case .code:
                applyRaw(.inlineCode, to: content, in: storage)
                markerToken = .syntaxMarker
            case .link, .image, .autolink:
                applyRaw(.link, to: content, in: storage)
                markerToken = .syntaxMarker
            case .strong:
                storage.addAttribute(
                    .font, value: theme.font(size: theme.codeSize, weight: 700, monospaced: true), range: content)
                applyRaw(.bold, to: content, in: storage)
                markerToken = .emphasisMarker
            case .emphasis:
                storage.addAttribute(
                    .font, value: theme.font(size: theme.codeSize, italic: true, monospaced: true), range: content)
                applyRaw(.italic, to: content, in: storage)
                markerToken = .emphasisMarker
            case .strikethrough:
                applyRaw(.strikethrough, to: content, in: storage)
                markerToken = .emphasisMarker
            }
            for marker in span.markers {
                let markerRange = NSRange(location: range.location + marker.lowerBound, length: marker.count)
                applyRaw(markerToken, to: markerRange, in: storage)
            }
            // A link's destination reads as a path, not syntax.
            if case .link = span.kind, let destination = span.markers.last, destination.count > 3 {
                applyRaw(
                    .linkDestination,
                    to: NSRange(location: range.location + destination.lowerBound + 2, length: destination.count - 3),
                    in: storage)
            }
        }
    }
}
