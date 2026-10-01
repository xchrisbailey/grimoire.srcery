import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Raw mode: every character in Geist Mono, markdown syntax colored by role (headings
/// mauve, list markers peach, quotes teal, MDX pink) and nothing hidden or drawn.
extension MarkdownStyler {
    var rawFont: PlatformFont { theme.font(size: theme.codeSize, monospaced: true) }

    var rawAttributes: [NSAttributedString.Key: Any] {
        [
            .font: rawFont, .foregroundColor: theme.ink,
            .paragraphStyle: paragraphStyle(lineHeight: theme.rawLineHeightMultiple),
        ]
    }

    func styleRawFront(_ storage: NSMutableAttributedString, index: BlockIndex, range: NSRange) {
        storage.setAttributes(rawAttributes, range: range)
        guard let frontmatter = index.frontmatterRange else { return }
        let text = storage.string as NSString
        forEachLine(of: NSRange(frontmatter), in: text) { line in
            let content = text.substring(with: line)
            if content.trimmingCharacters(in: .whitespaces) == "---" {
                storage.addAttribute(.foregroundColor, value: theme.faint, range: line)
            } else if let colon = content.firstIndex(of: ":") {
                let keyLength = content[..<colon].utf16.count
                storage.addAttribute(
                    .foregroundColor, value: theme.link, range: NSRange(location: line.location, length: keyLength))
                storage.addAttribute(
                    .foregroundColor, value: theme.string,
                    range: NSRange(location: line.location + keyLength + 1, length: line.length - keyLength - 1))
            }
        }
    }

    func styleRawBlock(_ kind: BlockKind, range: NSRange, fullRange: NSRange, in storage: NSMutableAttributedString) {
        storage.setAttributes(rawAttributes, range: fullRange)
        let text = storage.string as NSString
        switch kind {
        case .heading:
            storage.addAttributes(
                [
                    .foregroundColor: theme.magic,
                    .font: theme.font(size: theme.codeSize, weight: 700, monospaced: true),
                ],
                range: range)
        case .listItem:
            let firstLine = NSIntersectionRange(
                text.lineRange(for: NSRange(location: range.location, length: 0)), range)
            let prefix = MarkdownSyntax.listPrefix(in: text.substring(with: firstLine))
            storage.addAttribute(
                .foregroundColor, value: theme.caret,
                range: NSRange(location: range.location + prefix.indent, length: prefix.marker + prefix.checkbox))
            styleRawInline(
                NSRange(location: range.location + prefix.length, length: range.length - prefix.length), in: storage)
        case .blockquote:
            storage.addAttribute(.foregroundColor, value: theme.subtext, range: range)
            forEachLine(of: range, in: text) { line in
                let marker = MarkdownSyntax.quoteMarker(in: text.substring(with: line))
                storage.addAttribute(
                    .foregroundColor, value: theme.quote, range: NSRange(location: line.location, length: marker))
            }
        case .codeBlock:
            styleRawFences(range, in: storage)
        case .thematicBreak, .table:
            storage.addAttribute(.foregroundColor, value: kind == .table ? theme.ink : theme.marker, range: range)
            if kind == .table { styleRawInline(range, in: storage) }
        case .html, .linkDefinitions:
            storage.addAttribute(.foregroundColor, value: kind == .html ? theme.subtext : theme.link, range: range)
        case .mdx:
            storage.addAttribute(.foregroundColor, value: theme.sparkle, range: range)
        case .paragraph, .image:
            styleRawInline(range, in: storage)
        }
    }

    /// Dims a fenced code block's fence lines.
    private func styleRawFences(_ range: NSRange, in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        guard MarkdownSyntax.isFenced(text.substring(with: range)) else { return }
        var lines: [NSRange] = []
        forEachLine(of: range, in: text) { lines.append($0) }
        if let first = lines.first { storage.addAttribute(.foregroundColor, value: theme.faint, range: first) }
        if lines.count > 1, let last = lines.last {
            storage.addAttribute(.foregroundColor, value: theme.faint, range: last)
        }
    }

    /// Colors inline syntax: dim markers, green code, blue link text, teal destinations.
    func styleRawInline(_ range: NSRange, in storage: NSMutableAttributedString) {
        guard range.length > 0 else { return }
        for span in InlineScanner.scan((storage.string as NSString).substring(with: range)) {
            let content = NSRange(location: range.location + span.content.lowerBound, length: span.content.count)
            switch span.kind {
            case .code:
                storage.addAttribute(.foregroundColor, value: theme.string, range: content)
            case .link, .image, .autolink:
                storage.addAttribute(.foregroundColor, value: theme.link, range: content)
            case .strong:
                storage.addAttribute(
                    .font, value: theme.font(size: theme.codeSize, weight: 700, monospaced: true), range: content)
            case .emphasis:
                storage.addAttribute(
                    .font, value: theme.font(size: theme.codeSize, italic: true, monospaced: true), range: content)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            }
            for marker in span.markers {
                let markerRange = NSRange(location: range.location + marker.lowerBound, length: marker.count)
                storage.addAttribute(.foregroundColor, value: theme.marker, range: markerRange)
            }
            // A link's destination reads as a path, not syntax.
            if case .link = span.kind, let destination = span.markers.last, destination.count > 3 {
                storage.addAttribute(
                    .foregroundColor, value: theme.quote,
                    range: NSRange(location: range.location + destination.lowerBound + 2, length: destination.count - 3)
                )
            }
        }
    }
}
