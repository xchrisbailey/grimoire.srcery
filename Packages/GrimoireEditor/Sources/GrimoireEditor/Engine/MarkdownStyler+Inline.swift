import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Styling for emphasis, code spans, links and images inside a block.
extension MarkdownStyler {
    func styleInline(_ range: NSRange, in storage: NSMutableAttributedString, baseFont: PlatformFont, reveal: Bool) {
        guard range.length > 0 else { return }
        let spans = InlineScanner.scan((storage.string as NSString).substring(with: range))
        guard !spans.isEmpty else { return }
        applyFonts(for: spans, in: range, of: storage, baseFont: baseFont)
        for span in spans {
            let content = NSRange(location: range.location + span.content.lowerBound, length: span.content.count)
            if let attributes = attributes(for: span.kind) {
                storage.addAttributes(attributes, range: content)
            }
            let markerToken: MarkdownToken
            switch span.kind {
            case .strong, .emphasis, .strikethrough: markerToken = .emphasisMarker
            default: markerToken = .syntaxMarker
            }
            for marker in span.markers {
                applyMarker(
                    NSRange(location: range.location + marker.lowerBound, length: marker.count), in: storage,
                    reveal: reveal, token: markerToken)
            }
        }
    }

    /// Sets fonts by run: each character's weight, slant and code-ness come from every
    /// span covering it, so `***both***` and `**bold `code`**` combine.
    private func applyFonts(
        for spans: [InlineSpan], in range: NSRange, of storage: NSMutableAttributedString, baseFont: PlatformFont
    ) {
        let bold = covered(by: spans, kind: { $0 == .strong }, length: range.length)
        let italic = covered(by: spans, kind: { $0 == .emphasis }, length: range.length)
        let code = covered(by: spans, kind: { $0 == .code }, length: range.length)
        let baseWeight: CGFloat = baseFont.pointSize > theme.bodySize + 1 ? 680 : 400
        var start = 0
        while start < range.length {
            var end = start + 1
            while end < range.length, bold[end] == bold[start], italic[end] == italic[start], code[end] == code[start] {
                end += 1
            }
            if bold[start] || italic[start] || code[start] {
                let font =
                    code[start]
                    ? theme.font(size: baseFont.pointSize * 0.9, monospaced: true)
                    : theme.font(
                        size: baseFont.pointSize, weight: bold[start] ? 700 : baseWeight, italic: italic[start])
                storage.addAttribute(
                    .font, value: font, range: NSRange(location: range.location + start, length: end - start))
            }
            start = end
        }
    }

    /// Which characters sit inside a span of the given kind.
    private func covered(by spans: [InlineSpan], kind: (InlineSpan.Kind) -> Bool, length: Int) -> [Bool] {
        var flags = [Bool](repeating: false, count: length)
        for span in spans where kind(span.kind) {
            for index in span.content.clamped(to: 0..<length) { flags[index] = true }
        }
        return flags
    }

    private func attributes(for kind: InlineSpan.Kind) -> [NSAttributedString.Key: Any]? {
        switch kind {
        case .code:
            theme.token(.inlineCode, raw: false).attributes
        case .strikethrough:
            theme.token(.strikethrough, raw: false).attributes
        case .link(let destination), .autolink(let destination):
            theme.token(.link, raw: false).attributes.merging([.grimoireLink: destination]) { $1 }
        case .image(let source):
            [.foregroundColor: theme.faint, .grimoireLink: source]
        case .strong:
            theme.token(.bold, raw: false).attributes
        case .emphasis:
            theme.token(.italic, raw: false).attributes
        }
    }
}
