import CoreGraphics
import Foundation
import GrimoireCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The code a fenced block holds, as the highlighter sees it.
public struct CodeKey: Hashable, Sendable {
    public var language: String
    public var code: String
}

/// Syntax colors inside fenced code blocks, in Preview and Raw. Highlighting runs off the
/// main thread; until it finishes, the block keeps the colors from its last version, moved
/// to follow the edit, so typing doesn't flicker.
extension MarkdownStyler {
    /// The lines between a fenced block's fences.
    func codeBody(of range: NSRange, in text: NSString) -> NSRange? {
        guard MarkdownSyntax.isFenced(text.substring(with: range)) else { return nil }
        var lines: [NSRange] = []
        forEachLine(of: range, in: text) { lines.append($0) }
        guard lines.count >= 2, let first = lines.first else { return nil }
        let start = NSMaxRange(text.lineRange(for: first))
        var end = NSMaxRange(range)
        if let last = lines.last, lines.count > 1,
            text.substring(with: last).trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "`" || $0 == "~" })
        {
            end = last.location
        }
        guard end >= start else { return nil }
        // Leave out the line break before the closing fence.
        var body = NSRange(location: start, length: end - start)
        if body.length > 0, text.character(at: NSMaxRange(body) - 1) == 10 { body.length -= 1 }
        return body
    }

    /// Colors the code in `block` (a fenced block's source) by its language.
    func highlightCode(_ block: NSRange, language: String?, in storage: NSMutableAttributedString, raw: Bool) {
        guard let language, CodeHighlighter.supports(language) else { return }
        let text = storage.string as NSString
        guard let body = codeBody(of: block, in: text), body.length > 0 else { return }
        let key = CodeKey(language: language.lowercased(), code: text.substring(with: body))
        let highlights: [CodeHighlight]
        if let cached = codeHighlights[key] {
            highlights = cached
        } else if highlightsSynchronously {
            highlights = highlighter.highlightSync(key.code, language: language)
            remember(highlights, for: key)
        } else {
            highlights = interimHighlights(for: key)
            request(key)
        }
        paint(highlights, in: body, of: storage)
    }

    private func paint(_ highlights: [CodeHighlight], in body: NSRange, of storage: NSMutableAttributedString) {
        let size = theme.codeSize
        for highlight in highlights {
            let range = NSRange(location: body.location + highlight.range.location, length: highlight.range.length)
            guard NSMaxRange(range) <= NSMaxRange(body) else { continue }
            let style = theme.code(highlight.token)
            storage.addAttributes(style.attributes, range: range)
            if style.bold == true || style.italic == true {
                storage.addAttribute(
                    .font,
                    value: theme.font(
                        size: size, weight: style.bold == true ? 700 : 400, italic: style.italic == true,
                        monospaced: true),
                    range: range)
            }
        }
    }

    // MARK: - Cache

    private func request(_ key: CodeKey) {
        guard !pendingCode.contains(key) else { return }
        pendingCode.insert(key)
        highlighter.highlight(key.code, language: key.language) { [weak self] highlights in
            Task { @MainActor in
                guard let self else { return }
                self.pendingCode.remove(key)
                self.remember(highlights, for: key)
                self.onCodeHighlighted?(key)
            }
        }
    }

    private func remember(_ highlights: [CodeHighlight], for key: CodeKey) {
        if codeHighlights.count > 200 { codeHighlights.removeAll() }
        codeHighlights[key] = highlights
        var recent = recentCode[key.language] ?? []
        recent.removeAll { $0.code == key.code }
        recent.insert((key.code, highlights), at: 0)
        recentCode[key.language] = Array(recent.prefix(4))
    }

    /// The last highlighting of a similar version of this code, moved to follow the edit:
    /// runs before the change keep their place, runs after it shift, runs it touched drop.
    func interimHighlights(for key: CodeKey) -> [CodeHighlight] {
        let new = Array(key.code.utf16)
        struct Match {
            var highlights: [CodeHighlight]
            var prefix: Int
            var suffix: Int
            var oldLength: Int
        }
        var best: Match?
        for entry in recentCode[key.language] ?? [] {
            let old = Array(entry.code.utf16)
            var prefix = 0
            while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < min(old.count, new.count) - prefix,
                old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
            {
                suffix += 1
            }
            if prefix + suffix > (best.map { $0.prefix + $0.suffix } ?? -1) {
                best = Match(highlights: entry.highlights, prefix: prefix, suffix: suffix, oldLength: old.count)
            }
        }
        guard let best, best.prefix + best.suffix >= new.count / 2 else { return [] }
        let delta = new.count - best.oldLength
        let tailStart = best.oldLength - best.suffix
        return best.highlights.compactMap { highlight in
            if NSMaxRange(highlight.range) <= best.prefix { return highlight }
            if highlight.range.location >= tailStart {
                var moved = highlight
                moved.range.location += delta
                return moved
            }
            return nil
        }
    }
}
