import Foundation

/// One replacement in a document's text, and where the selection goes afterwards.
/// Ranges are UTF-16 offsets.
public struct TextEdit: Equatable, Sendable {
    /// The range replaced, in the text before the edit.
    public var range: Range<Int>
    public var replacement: String
    /// The selection after the edit, in the new text.
    public var selection: Range<Int>

    public init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// An edit that changes nothing, for a key that was handled but had nothing to do.
    public static func none(keeping selection: Range<Int>) -> TextEdit {
        TextEdit(range: selection.lowerBound..<selection.lowerBound, replacement: "", selection: selection)
    }

    public var isEmpty: Bool { range.isEmpty && replacement.isEmpty }

    /// `text` with the edit applied.
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(
            in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
    }

    /// The smallest edit that turns `old` into `new`, by trimming their common prefix and
    /// suffix.
    public static func difference(from old: String, to new: String, selection: Range<Int>) -> TextEdit {
        let oldUnits = Array(old.utf16)
        let newUnits = Array(new.utf16)
        var prefix = 0
        while prefix < oldUnits.count, prefix < newUnits.count, oldUnits[prefix] == newUnits[prefix] { prefix += 1 }
        // Don't split a surrogate pair.
        if prefix > 0, prefix < oldUnits.count, UTF16.isTrailSurrogate(oldUnits[prefix]) { prefix -= 1 }
        var suffix = 0
        while suffix < oldUnits.count - prefix, suffix < newUnits.count - prefix,
            oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix]
        {
            suffix += 1
        }
        if suffix > 0, oldUnits.count - suffix < oldUnits.count,
            UTF16.isTrailSurrogate(oldUnits[oldUnits.count - suffix])
        {
            suffix -= 1
        }
        let replacement = String(decoding: newUnits[prefix..<(newUnits.count - suffix)], as: UTF16.self)
        return TextEdit(range: prefix..<(oldUnits.count - suffix), replacement: replacement, selection: selection)
    }
}
