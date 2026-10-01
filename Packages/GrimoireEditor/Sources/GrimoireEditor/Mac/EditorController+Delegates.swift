#if os(macOS)
import AppKit
import GrimoireCore

/// The text system's callbacks: edits update the index and restyle, selection changes
/// reveal markers and keep focus mode and the Spells menu in step.
extension EditorController: NSTextStorageDelegate {
    public nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        nonisolated(unsafe) let textStorage = textStorage
        MainActor.assumeIsolated {
            guard !isLoading else { return }
            let oldRange = editedRange.location..<(editedRange.location + editedRange.length - delta)
            let changed = index.replace(oldRange, replacementLength: editedRange.length, in: textStorage.string)
            let full = changed.count == index.blocks.count
            revealed = index.blockIndex(at: NSMaxRange(editedRange))
            styler.caret = NSMaxRange(editedRange)
            if full {
                styler.styleAll(textStorage, index: index, revealing: revealed)
            } else {
                var blocks = changed
                if let revealed, !blocks.contains(revealed) {
                    blocks = min(blocks.lowerBound, revealed)..<max(blocks.upperBound, revealed + 1)
                }
                styler.style(textStorage, index: index, blocks: blocks, revealing: revealed)
            }
        }
    }
}

extension EditorController: NSTextViewDelegate {
    public func undoManager(for view: NSTextView) -> UndoManager? {
        undoManager
    }

    public func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        let items = spellingMenuItems(at: charIndex) + tableMenuItems(at: charIndex)
        for (position, item) in items.enumerated() { menu.insertItem(item, at: position) }
        return menu
    }

    public func textDidChange(_ notification: Notification) {
        blockHandle.hide()
        codeChrome.update()
        if dimsAroundCaret {
            litBlock = nil
            updateDimming()
        }
        if pendingShortcut {
            pendingShortcut = false
            if let edit = editing.shortcut() { apply(edit) }
        }
        if spellSession != nil {
            updateSpells()
        } else if let slash = pendingSlash, mode == .preview {
            pendingSlash = nil
            openSpells(at: slash)
        }
        let text = textView.string
        lastText = text
        if proxy?.isFindVisible == true { updateFindMatches() }
        onTextChange?(text)
        centerCaret()
    }

    public func textView(
        _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?
    ) -> Bool {
        // Shortcuts expand right after the character that completes them.
        pendingShortcut = !isApplying && mode == .preview && (text == " " || text == "`" || text == "~")
        pendingSlash = !isApplying && text == "/" ? range.location : nil
        if text == "/", spellSession?.isFreshSpells(at: range.location) == true {
            // "//" closes the menu and leaves one literal slash.
            closeSpells()
            return false
        }
        return true
    }

    public func textView(
        _ view: NSTextView, willCheckTextIn range: NSRange, options: [NSSpellChecker.OptionKey: Any] = [:],
        types checkingTypes: UnsafeMutablePointer<NSTextCheckingTypes>
    ) -> [NSSpellChecker.OptionKey: Any] {
        checkingOptions(options)
    }

    // swiftlint:disable:next function_parameter_count
    public func textView(
        _ view: NSTextView, didCheckTextIn range: NSRange, types checkingTypes: NSTextCheckingTypes,
        options: [NSSpellChecker.OptionKey: Any] = [:], results: [NSTextCheckingResult], orthography: NSOrthography,
        wordCount: Int
    ) -> [NSTextCheckingResult] {
        filterCheckingResults(results, in: range)
    }

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        handleCommand(selector)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        keepStreamedTextOnClick()
        // Arrow keys keep the line centered; clicks leave the page where it is.
        if typewriterScrolling, NSApp.currentEvent?.type == .keyDown { centerCaret() }
        if dimsAroundCaret { updateDimming() }
        if spellSession != nil, !isApplying { closeSpellsIfCaretLeft() }
        codeChrome.update()
        guard mode == .preview else { return }
        let block = caretBlock()
        formatTableIfLeft(for: block)
        guard block != revealed else {
            // Within a table, markers show only on the caret's row, so moving rows restyles it.
            if let block, index.blocks[block].kind == .table, !isApplying { restyle(block..<(block + 1)) }
            return
        }
        let previous = revealed
        revealed = block
        var touched: [Int] = []
        if let previous, previous < index.blocks.count { touched.append(previous) }
        if let block { touched.append(block) }
        for position in touched { restyle(position..<(position + 1)) }
    }
}

extension EditorController {
    /// Leaving a table tidies its pipes, once the selection change has finished.
    private func formatTableIfLeft(for block: Int?) {
        guard let previous = revealed, previous != block, previous < index.blocks.count,
            index.blocks[previous].kind == .table, !isApplying
        else { return }
        let table = index.blocks[previous].id
        DispatchQueue.main.async { [weak self] in self?.formatTable(id: table) }
    }
}

extension EditorController: NSTextLayoutManagerDelegate {
    public nonisolated func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        guard let decoration = MarkdownLayoutFragment.decoration(of: textElement) else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        let theme = MainActor.assumeIsolated { styler.theme }
        return MarkdownLayoutFragment(
            textElement: textElement, range: textElement.elementRange, decoration: decoration, theme: theme)
    }
}
#endif
