#if os(macOS)
import AppKit
import GrimoireCore

/// Auto-pairing: an opening bracket, quote or backtick brings its closing one, typing the
/// closing one steps over it, Backspace in an empty pair removes both, and a bracket,
/// quote or marker typed over a selection wraps it.
extension EditorController {
    private static let brackets: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    private static let quotes: Set<Character> = ["\"", "'", "`"]
    /// Markers that only wrap a selection, since on their own they start lists and rules.
    private static let markers: Set<Character> = ["*", "_", "~", "="]
    private static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`", "\u{201D}", "\u{2019}"]

    /// Handles one typed character. Returns true when it was paired, wrapped or stepped
    /// over, so the text view shouldn't insert it.
    func handlePairing(_ typed: String) -> Bool {
        guard autoPairs, !isApplying, typed.count == 1, let character = typed.first, !textView.hasMarkedText()
        else { return false }
        let selection = textView.selectedRange()
        let text = textView.string as NSString
        let next =
            selection.length == 0 && NSMaxRange(selection) < text.length
            ? char(at: NSMaxRange(selection), in: text) : nil
        let previous = selection.location > 0 ? char(at: selection.location - 1, in: text) : nil

        if selection.length > 0 {
            guard let (open, close) = pair(for: character, wrapping: true) else { return false }
            let inner = text.substring(with: selection)
            let start = selection.location + (open as NSString).length
            apply(
                TextEdit(
                    range: selection.location..<NSMaxRange(selection), replacement: open + inner + close,
                    selection: start..<(start + (inner as NSString).length)))
            return true
        }
        if Self.closers.contains(character), let next, next == character || next == smartCloser(character) {
            textView.setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return true
        }
        guard let (open, close) = pair(for: character, wrapping: false),
            next.map({ $0.isWhitespace || ")]}>,.;:!?".contains($0) || Self.closers.contains($0) }) ?? true
        else { return false }
        if Self.quotes.contains(character) {
            // Not after a letter (it's an apostrophe), and three backticks make a fence.
            if let previous, previous.isLetter || previous.isNumber || previous == "`" { return false }
        }
        let caret = selection.location + (open as NSString).length
        apply(
            TextEdit(
                range: selection.location..<selection.location, replacement: open + close, selection: caret..<caret))
        return true
    }

    /// Backspace between an empty pair removes both halves.
    func deletePair() -> Bool {
        guard autoPairs else { return false }
        let selection = textView.selectedRange()
        let text = textView.string as NSString
        guard selection.length == 0, selection.location > 0, selection.location < text.length else { return false }
        let before = char(at: selection.location - 1, in: text)
        let after = char(at: selection.location, in: text)
        let matches =
            Self.brackets[before] == after || (Self.quotes.contains(before) && before == after)
            || (before == "\u{201C}" && after == "\u{201D}") || (before == "\u{2018}" && after == "\u{2019}")
        guard matches else { return false }
        apply(
            TextEdit(
                range: (selection.location - 1)..<(selection.location + 1), replacement: "",
                selection: (selection.location - 1)..<(selection.location - 1)))
        return true
    }

    /// The opening and closing text for `character`, curly when smart quotes apply.
    private func pair(for character: Character, wrapping: Bool) -> (String, String)? {
        if let close = Self.brackets[character] { return (String(character), String(close)) }
        if character == "\"" || character == "'", usesSmartQuotes {
            return character == "\"" ? ("\u{201C}", "\u{201D}") : ("\u{2018}", "\u{2019}")
        }
        if Self.quotes.contains(character) { return (String(character), String(character)) }
        if wrapping, Self.markers.contains(character) {
            let marker =
                character == "~" || character == "=" ? String(repeating: character, count: 2) : String(character)
            return (marker, marker)
        }
        return nil
    }

    /// The curly closing quote a straight one stands for, when smart quotes apply.
    private func smartCloser(_ character: Character) -> Character? {
        guard usesSmartQuotes else { return nil }
        switch character {
        case "\"": return "\u{201D}"
        case "'": return "\u{2019}"
        default: return nil
        }
    }

    /// Smart quotes are on and the caret is in prose, not Raw or a code block.
    private var usesSmartQuotes: Bool {
        guard textChecking.smartQuotes, mode == .preview else { return false }
        guard let block = caretBlock() else { return true }
        if case .codeBlock = index.blocks[block].kind { return false }
        return true
    }

    private func char(at offset: Int, in text: NSString) -> Character {
        Character(UnicodeScalar(text.character(at: offset)) ?? " ")
    }
}
#endif
