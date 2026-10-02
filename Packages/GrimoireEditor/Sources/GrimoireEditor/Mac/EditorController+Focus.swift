#if os(macOS)
import AppKit
import GrimoireCore

/// Focus mode's fade: everything but the caret's paragraph or sentence draws in the
/// marker color.
extension EditorController {
    /// Fades all but the lit text with a rendering attribute, which changes how text draws
    /// without touching the text storage.
    func updateDimming() {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage else { return }
        let lit = dimsAroundCaret ? litRangeAroundCaret() : nil
        guard lit != litRange || !dimsAroundCaret else { return }
        litRange = lit
        let documentRange = storage.documentRange
        layoutManager.removeRenderingAttribute(.foregroundColor, for: documentRange)
        guard dimsAroundCaret else { return }
        let dim = styler.theme.marker
        let length = (textView.string as NSString).length
        var ranges: [NSRange] = []
        if let lit {
            ranges.append(NSRange(location: 0, length: lit.location))
            ranges.append(NSRange(location: NSMaxRange(lit), length: length - NSMaxRange(lit)))
        } else {
            ranges.append(NSRange(location: 0, length: length))
        }
        for range in ranges where range.length > 0 {
            guard let start = storage.location(documentRange.location, offsetBy: range.location),
                let end = storage.location(start, offsetBy: range.length),
                let textRange = NSTextRange(location: start, end: end)
            else { continue }
            layoutManager.addRenderingAttribute(.foregroundColor, value: dim, for: textRange)
        }
    }

    /// The caret's block, or in sentence focus the sentence holding the caret. Code,
    /// tables and other blocks without sentences stay lit whole.
    private func litRangeAroundCaret() -> NSRange? {
        let caret = textView.selectedRange().location
        guard let block = index.blockIndex(at: caret) else { return nil }
        let range = NSRange(index.sourceRange(of: block))
        switch index.blocks[block].kind {
        case .paragraph, .listItem, .blockquote, .heading:
            guard focusUnit == .sentence else { return range }
            return Sentences.range(around: caret, in: range, of: textView.string) ?? range
        default:
            return range
        }
    }
}
#endif
