import Foundation
import NaturalLanguage

/// Finds sentences in prose, for sentence focus.
enum Sentences {
    /// The sentence in `block` (a range of `text`) that holds `offset`, trailing spaces
    /// included so the next sentence starts lit as soon as the caret reaches it.
    static func range(around offset: Int, in block: NSRange, of text: String) -> NSRange? {
        let string = text as NSString
        guard block.length > 0, NSMaxRange(block) <= string.length else { return nil }
        let source = string.substring(with: block)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source
        let local = offset - block.location
        var found: NSRange?
        tokenizer.enumerateTokens(in: source.startIndex..<source.endIndex) { tokenRange, _ in
            let range = NSRange(tokenRange, in: source)
            // The caret right after a sentence's last character still belongs to it.
            if local >= range.location, local <= NSMaxRange(range) {
                found = NSRange(location: block.location + range.location, length: range.length)
                if local < NSMaxRange(range) { return false }
            }
            return true
        }
        return found
    }
}
