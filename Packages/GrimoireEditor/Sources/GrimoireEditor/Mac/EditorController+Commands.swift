#if os(macOS)
import AppKit
import GrimoireCore

/// Keys and commands that act on blocks: Enter, Backspace, Tab, moving and duplicating
/// blocks, toggling tasks and turning blocks into other kinds.
extension EditorController {
    var editing: BlockEditing {
        let selection = textView.selectedRange()
        return BlockEditing(
            text: textView.string, index: index, selection: selection.location..<NSMaxRange(selection))
    }

    /// Makes `edit` through the text view, so it's undoable and the index follows it.
    func apply(_ edit: TextEdit, actionName: String? = nil) {
        guard !edit.isEmpty else {
            textView.setSelectedRange(NSRange(edit.selection))
            return
        }
        let range = NSRange(edit.range)
        guard textView.shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        isApplying = true
        if actionName != nil { textView.breakUndoCoalescing() }
        textView.textStorage?.replaceCharacters(in: range, with: edit.replacement)
        textView.setSelectedRange(NSRange(edit.selection))
        textView.didChangeText()
        isApplying = false
        if let actionName { textView.undoManager?.setActionName(actionName) }
        textView.scrollRangeToVisible(NSRange(edit.selection))
    }

    /// Handles the text view's standard commands. Returns false to let it act as usual.
    func handleCommand(_ selector: Selector) -> Bool {
        if let handled = handleModalCommand(selector) { return handled }
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let edit: TextEdit?
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            edit = editing.newline(soft: shift)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
            edit = editing.newline(soft: true)
        case #selector(NSResponder.deleteBackward(_:)):
            edit = editing.backspace()
        case #selector(NSResponder.insertTab(_:)):
            edit = editing.indent(outdent: false)
        case #selector(NSResponder.insertBacktab(_:)):
            edit = editing.indent(outdent: true)
        default:
            return handleBlockCommand(selector)
        }
        guard let edit else { return false }
        apply(edit)
        return true
    }

    /// Commands something else gets first: the open Spells menu, focus mode's Escape, Raw
    /// mode, and tables. Nil when none of them claims it.
    private func handleModalCommand(_ selector: Selector) -> Bool? {
        if spellSession != nil, handleSpellsCommand(selector) { return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), onEscape?() == true { return true }
        if mode == .raw { return handleRawCommand(selector) }
        if editing.tableCell != nil, let handled = handleTableCommand(selector) { return handled }
        return nil
    }

    /// Raw mode keeps one block behavior: Enter continues a list.
    private func handleRawCommand(_ selector: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        guard selector == #selector(NSResponder.insertNewline(_:)), !shift,
            let block = editing.currentBlock, index.blocks[block].kind.isListItem,
            let edit = editing.newline()
        else { return false }
        apply(edit)
        return true
    }

    /// ⌥⇧↑ and ⌥⇧↓ move the block; Esc selects it.
    private func handleBlockCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveParagraphBackwardAndModifySelection(_:)):
            return perform(editing.moveBlock(upward: true), actionName: String(localized: "Move Block"))
        case #selector(NSResponder.moveParagraphForwardAndModifySelection(_:)):
            return perform(editing.moveBlock(upward: false), actionName: String(localized: "Move Block"))
        case #selector(NSResponder.cancelOperation(_:)):
            guard let block = editing.blockSelection() else { return false }
            textView.setSelectedRange(NSRange(block))
            return true
        default:
            return false
        }
    }

    /// Key equivalents the text view doesn't map to commands: ⌘↩ toggles a task and ⇧⌘D
    /// duplicates the block.
    func handleKey(_ event: NSEvent) -> Bool {
        guard mode == .preview else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 {
            return perform(editing.toggleTask(), actionName: String(localized: "Toggle Task"))
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "d" {
            return perform(editing.duplicateBlock(), actionName: String(localized: "Duplicate Block"))
        }
        return false
    }

    @discardableResult
    func perform(_ edit: TextEdit?, actionName: String) -> Bool {
        guard let edit else { return false }
        apply(edit, actionName: actionName)
        return true
    }

    /// Selects the whole block at `offset`, for ⌘-click.
    func selectBlock(at offset: Int) {
        guard let position = index.blockIndex(at: offset) else { return }
        textView.setSelectedRange(NSRange(index.sourceRange(of: position)))
    }

    // MARK: - Block menu

    public func moveBlock(_ source: Int, to destination: Int) {
        perform(editing.moveBlock(source, to: destination), actionName: String(localized: "Move Block"))
    }

    public func duplicateBlock(_ position: Int) {
        placeCaret(in: position)
        perform(editing.duplicateBlock(), actionName: String(localized: "Duplicate Block"))
    }

    public func deleteBlock(_ position: Int) {
        perform(editing.deleteBlock(position), actionName: String(localized: "Delete Block"))
    }

    public func convertBlock(_ position: Int, to kind: BlockKind) {
        placeCaret(in: position)
        perform(editing.convert(position, to: kind), actionName: String(localized: "Turn Into"))
    }

    private func placeCaret(in position: Int) {
        let source = index.sourceRange(of: position)
        let selection = textView.selectedRange()
        if !source.contains(selection.location) {
            textView.setSelectedRange(NSRange(location: source.upperBound, length: 0))
        }
    }
}
#endif
