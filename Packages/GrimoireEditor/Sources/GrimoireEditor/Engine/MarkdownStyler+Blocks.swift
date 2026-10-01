import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Styling for headings, lists, quotes, code and images.
extension MarkdownStyler {
    func styleHeading(level: Int, range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        let font = theme.heading(level)
        let spacing: CGFloat = level <= 2 ? font.pointSize * 0.3 : 0
        storage.addAttributes(
            [.font: font, .paragraphStyle: paragraphStyle(lineHeight: 1.1, spacingBefore: spacing)], range: range)
        applyPreview(.heading(level), to: range, in: storage)
        let text = (storage.string as NSString).substring(with: range)
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.count > 1, let underline = lines.last {
            // Setext: the underline is the marker.
            let length = underline.utf16.count
            applyMarker(NSRange(location: NSMaxRange(range) - length, length: length), in: storage, reveal: reveal)
            styleInline(
                NSRange(location: range.location, length: range.length - length), in: storage, baseFont: font,
                reveal: reveal)
            return
        }
        let (prefix, suffixStart) = MarkdownSyntax.headingMarkers(in: text)
        applyMarker(NSRange(location: range.location, length: prefix), in: storage, reveal: reveal)
        applyMarker(
            NSRange(location: range.location + suffixStart, length: range.length - suffixStart), in: storage,
            reveal: reveal)
        styleInline(
            NSRange(location: range.location + prefix, length: max(0, suffixStart - prefix)), in: storage,
            baseFont: font, reveal: reveal)
    }

    func styleListItem(_ item: ListItem, range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        let text = storage.string as NSString
        let firstLine = NSIntersectionRange(text.lineRange(for: NSRange(location: range.location, length: 0)), range)
        let prefix = MarkdownSyntax.listPrefix(in: text.substring(with: firstLine))
        let level = CGFloat(item.indent) * theme.listIndent
        let markerRange = NSRange(location: range.location, length: prefix.length)
        let content = NSRange(location: range.location + prefix.length, length: range.length - prefix.length)

        switch (item.marker, item.checkbox) {
        case (_, .some(let checkbox)):
            styleDrawnMarker(
                .task(checked: checkbox == .checked, indent: level), level: level, range: range, in: storage,
                reveal: reveal)
            applyMarker(markerRange, in: storage, reveal: reveal, token: .listMarker)
            if checkbox == .checked {
                storage.addAttributes(
                    [
                        .foregroundColor: theme.faint, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: theme.marker,
                    ],
                    range: content)
            }
        case (.bullet, nil):
            styleDrawnMarker(.bullet(indent: level), level: level, range: range, in: storage, reveal: reveal)
            applyMarker(markerRange, in: storage, reveal: reveal, token: .listMarker)
        case (.ordered, nil):
            storage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(firstLineIndent: level, indent: level + LineDecoration.taskWidth),
                range: range)
            // Numbers stay visible: they carry information.
            storage.addAttributes(
                [.foregroundColor: theme.token(.listMarker, raw: false).color ?? theme.caret, .grimoireMarker: true],
                range: NSRange(location: range.location + prefix.indent, length: prefix.marker))
            if !reveal {
                storage.addAttributes(
                    [.font: EditorTheme.hiddenFont, .foregroundColor: PlatformColor.clear],
                    range: NSRange(location: range.location, length: prefix.indent))
            }
        }
        styleInline(content, in: storage, baseFont: theme.body, reveal: reveal)
    }

    /// Indents a bullet or task item and, off the caret's block, draws its marker.
    private func styleDrawnMarker(
        _ decoration: LineDecoration.Kind, level: CGFloat, range: NSRange, in storage: NSMutableAttributedString,
        reveal: Bool
    ) {
        let width = decoration == .bullet(indent: level) ? LineDecoration.bulletWidth : LineDecoration.taskWidth
        let text = storage.string as NSString
        let firstLine = NSIntersectionRange(text.lineRange(for: NSRange(location: range.location, length: 0)), range)
        storage.addAttribute(
            .paragraphStyle,
            value: paragraphStyle(firstLineIndent: level + (reveal ? 0 : width), indent: level + width),
            range: range)
        if !reveal {
            storage.addAttribute(.grimoireDecoration, value: LineDecoration(decoration), range: firstLine)
        }
    }

    func styleQuote(_ range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        let text = storage.string as NSString
        storage.addAttributes(
            [.foregroundColor: theme.subtext, .paragraphStyle: paragraphStyle(firstLineIndent: 16, indent: 16)],
            range: range)
        applyPreview(.quote, to: range, in: storage)
        forEachLine(of: range, in: text) { line in
            storage.addAttribute(.grimoireDecoration, value: LineDecoration(.quote), range: line)
            let marker = MarkdownSyntax.quoteMarker(in: text.substring(with: line))
            applyMarker(NSRange(location: line.location, length: marker), in: storage, reveal: reveal)
            styleInline(
                NSRange(location: line.location + marker, length: line.length - marker), in: storage,
                baseFont: theme.body, reveal: reveal)
        }
    }

    func styleCode(_ range: NSRange, in storage: NSMutableAttributedString, fenced: Bool) {
        let text = storage.string as NSString
        storage.addAttributes(
            [
                .font: theme.code, .foregroundColor: theme.token(.codeBlock, raw: false).color ?? theme.ink,
                .paragraphStyle: paragraphStyle(firstLineIndent: 14, indent: 14, tailIndent: -14, lineHeight: 1.15),
            ],
            range: range)
        var lines: [NSRange] = []
        forEachLine(of: range, in: text) { lines.append($0) }
        for (number, line) in lines.enumerated() {
            let position: LineDecoration.Position =
                lines.count == 1 ? .only : number == 0 ? .first : number == lines.count - 1 ? .last : .middle
            // Include the line break, so the background covers the whole line.
            var covered = line
            if NSMaxRange(line) < storage.length, NSMaxRange(line) <= NSMaxRange(range) {
                covered = text.lineRange(for: line)
            }
            storage.addAttribute(.grimoireDecoration, value: LineDecoration(.code(position)), range: covered)
        }
        guard fenced, let first = lines.first else { return }
        let fence = theme.token(.codeFence, raw: false).color ?? theme.marker
        storage.addAttributes([.foregroundColor: fence, .grimoireMarker: true], range: first)
        if lines.count > 1, let last = lines.last,
            text.substring(with: last).trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "`" || $0 == "~" })
        {
            storage.addAttributes([.foregroundColor: fence, .grimoireMarker: true], range: last)
        }
    }

    func styleImage(_ range: NSRange, in storage: NSMutableAttributedString, reveal: Bool) {
        styleInline(range, in: storage, baseFont: theme.body, reveal: reveal)
        let text = (storage.string as NSString).substring(with: range)
        guard case .image(let source) = InlineScanner.scan(text).first?.kind,
            let url = resolve(source)
        else { return }
        guard let image = images.image(for: url) else {
            images.load(url) { [weak self] image in
                if image != nil { self?.onImageLoaded?(url) }
            }
            return
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, theme.maxLineWidth / max(width, 1), 360 / max(height, 1))
        let size = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        storage.addAttributes(
            [
                .grimoireDecoration: LineDecoration(.image(url: url, size: size)),
                .paragraphStyle: paragraphStyle(spacingAfter: size.height + LineDecoration.imageGap * 2),
            ],
            range: range)
    }

    /// A file URL for an image path, relative to the document's folder.
    public func resolve(_ source: String) -> URL? {
        let path = source.removingPercentEncoding ?? source
        if let url = URL(string: source), url.scheme != nil { return url.isFileURL ? url : nil }
        if path.hasPrefix("/") { return URL(filePath: path) }
        return baseURL?.appending(path: path).standardizedFileURL
    }
}
