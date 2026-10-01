import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Turns rich text copied from a browser into markdown: headings, bold, italic, code,
/// links and lists. Anything else comes through as plain text.
@MainActor
public enum HTMLToMarkdown {
    /// Markdown for an HTML fragment, or nil when it can't be read.
    public static func convert(html: Data) -> String? {
        guard
            let attributed = try? NSAttributedString(
                data: html,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil)
        else { return nil }
        return convert(attributed)
    }

    /// Markdown for rich text: headings come from font sizes, lists from text lists.
    public static func convert(_ attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        let baseSize = mostCommonFontSize(in: attributed)
        var blocks: [(markdown: String, isListItem: Bool)] = []
        let whole = NSRange(location: 0, length: text.length)
        text.enumerateSubstrings(in: whole, options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { return }
            let paragraph = attributed.attributedSubstring(from: range)
            let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            if let lists = style?.textLists, let list = lists.last {
                let depth = lists.count - 1
                let ordered = list.markerFormat.rawValue.contains("decimal")
                let number = list.startingItemNumber + countPreviousItems(in: blocks, depth: depth)
                let marker = ordered ? "\(number)." : "-"
                let body = inline(stripListMarker(paragraph))
                blocks.append((String(repeating: "  ", count: depth) + marker + " " + body, true))
                return
            }
            let body = inline(paragraph).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return }
            let font = paragraph.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
            let level = headingLevel(size: font?.pointSize ?? baseSize, base: baseSize)
            let prefix = level.map { String(repeating: "#", count: $0) + " " } ?? ""
            blocks.append((prefix + (level == nil ? body : plain(paragraph)), false))
        }
        var output = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 { output += block.isListItem && blocks[index - 1].isListItem ? "\n" : "\n\n" }
            output += block.markdown
        }
        return output
    }

    // MARK: - Inline

    private static func inline(_ paragraph: NSAttributedString) -> String {
        var output = ""
        let string = paragraph.string as NSString
        paragraph.enumerateAttributes(in: NSRange(location: 0, length: paragraph.length)) { attributes, range, _ in
            var piece = string.substring(with: range).replacingOccurrences(of: "\n", with: " ")
            guard !piece.trimmingCharacters(in: .whitespaces).isEmpty else {
                output += piece
                return
            }
            let leading = String(piece.prefix { $0 == " " })
            let trailing = String(piece.reversed().prefix { $0 == " " })
            piece = piece.trimmingCharacters(in: .whitespaces)
            let font = attributes[.font] as? PlatformFont
            let traits = font.map(symbolicTraits) ?? Traits()
            if traits.isMonospace {
                piece = "`\(piece)`"
            } else {
                if traits.isItalic { piece = "_\(piece)_" }
                if traits.isBold { piece = "**\(piece)**" }
            }
            if let link = attributes[.link] {
                let url = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
                piece = "[\(piece)](\(url))"
            }
            output += leading + piece + trailing
        }
        return output
    }

    private static func plain(_ paragraph: NSAttributedString) -> String {
        paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Traits {
        var isBold = false
        var isItalic = false
        var isMonospace = false
    }

    private static func symbolicTraits(_ font: PlatformFont) -> Traits {
        let traits = CTFontGetSymbolicTraits(font as CTFont)
        return Traits(
            isBold: traits.contains(.traitBold), isItalic: traits.contains(.traitItalic),
            isMonospace: traits.contains(.traitMonoSpace))
    }

    // MARK: - Structure

    /// AppKit puts "\t•\t" or "\t1.\t" before each list item's text.
    private static func stripListMarker(_ paragraph: NSAttributedString) -> NSAttributedString {
        let string = paragraph.string as NSString
        guard string.hasPrefix("\t") else { return paragraph }
        let second = string.range(of: "\t", range: NSRange(location: 1, length: max(0, string.length - 1)))
        guard second.location != NSNotFound else { return paragraph }
        let start = NSMaxRange(second)
        return paragraph.attributedSubstring(from: NSRange(location: start, length: string.length - start))
    }

    private static func countPreviousItems(in blocks: [(markdown: String, isListItem: Bool)], depth: Int) -> Int {
        let indent = String(repeating: "  ", count: depth)
        var count = 0
        for block in blocks.reversed() {
            guard block.isListItem else { break }
            let line = block.markdown
            if line.hasPrefix(indent), !line.dropFirst(indent.count).hasPrefix(" ") { count += 1 }
        }
        return count
    }

    private static func headingLevel(size: CGFloat, base: CGFloat) -> Int? {
        switch size / max(base, 1) {
        case 1.7...: 1
        case 1.35...: 2
        case 1.15...: 3
        default: nil
        }
    }

    private static func mostCommonFontSize(in attributed: NSAttributedString) -> CGFloat {
        var counts: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let font = value as? PlatformFont { counts[font.pointSize, default: 0] += range.length }
        }
        return counts.max { $0.value < $1.value }?.key ?? 12
    }
}
