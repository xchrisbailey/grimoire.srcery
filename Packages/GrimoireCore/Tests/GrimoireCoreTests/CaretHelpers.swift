import Foundation

@testable import GrimoireCore

/// Text with `‸` marking the caret.
func caretText(_ marked: String) -> (String, Int) {
    let range = (marked as NSString).range(of: "‸")
    return ((marked as NSString).replacingCharacters(in: range, with: ""), range.location)
}

/// Runs `action` on `marked` and returns the result with the caret marked again, or nil
/// when the action declined.
func run(_ marked: String, _ action: (BlockEditing) -> TextEdit?) -> String? {
    let (text, caret) = caretText(marked)
    let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: caret..<caret)
    guard let edit = action(editing) else { return nil }
    let result = edit.applied(to: text) as NSString
    return result.replacingCharacters(in: NSRange(location: edit.selection.lowerBound, length: 0), with: "‸")
}
