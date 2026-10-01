#if os(macOS)
import AppKit
import GrimoireCore

/// Find and replace in the open file: every match is tinted, the current one selected.
extension EditorController {
    var selectedText: String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    /// Recomputes the matches and their tint after the query, options or text change.
    func updateFindMatches() {
        guard let proxy else { return }
        findMatches = proxy.isFindVisible ? proxy.search.matches(in: textView.string, limit: 10_000) : []
        proxy.matchCount = findMatches.count
        let selection = textView.selectedRange()
        proxy.currentMatch = findMatches.firstIndex { $0 == selection }
        tintFindMatches()
    }

    private func tintFindMatches() {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage else { return }
        layoutManager.removeRenderingAttribute(.backgroundColor, for: storage.documentRange)
        let tint = styler.theme.magic.withAlphaComponent(0.22)
        for match in findMatches {
            guard let start = storage.location(storage.documentRange.location, offsetBy: match.location),
                let end = storage.location(start, offsetBy: match.length),
                let range = NSTextRange(location: start, end: end)
            else { continue }
            layoutManager.addRenderingAttribute(.backgroundColor, value: tint, for: range)
        }
    }

    /// Selects the next match after the selection (or the previous one before it),
    /// wrapping around the document.
    func findNext(backward: Bool) {
        guard let proxy else { return }
        if findMatches.isEmpty { updateFindMatches() }
        guard !findMatches.isEmpty else {
            NSSound.beep()
            return
        }
        let selection = textView.selectedRange()
        let index: Int
        if backward {
            index = findMatches.lastIndex { $0.location < selection.location } ?? findMatches.count - 1
        } else {
            index = findMatches.firstIndex { $0.location >= NSMaxRange(selection) && $0 != selection } ?? 0
        }
        select(findMatches[index])
        proxy.currentMatch = index
    }

    private func select(_ range: NSRange) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    /// Replaces the selected match and moves to the next one.
    func replaceCurrentMatch() {
        guard let proxy else { return }
        let selection = textView.selectedRange()
        guard findMatches.contains(selection) else { return findNext(backward: false) }
        let text = textView.string
        let replacement = proxy.search.replacement(for: selection, in: text, template: proxy.replacement)
        let end = selection.location + replacement.utf16.count
        apply(
            TextEdit(range: selection.location..<NSMaxRange(selection), replacement: replacement, selection: end..<end),
            actionName: String(localized: "Replace"))
        updateFindMatches()
        findNext(backward: false)
    }

    /// Replaces every match in one undoable step.
    func replaceAllMatches() {
        guard let proxy else { return }
        updateFindMatches()
        guard !findMatches.isEmpty else { return NSSound.beep() }
        onBeforeLargeEdit?(.replaceAll)
        let text = textView.string
        let result = NSMutableString(string: text)
        for match in findMatches.reversed() {
            result.replaceCharacters(
                in: match, with: proxy.search.replacement(for: match, in: text, template: proxy.replacement))
        }
        let caret = min(textView.selectedRange().location, result.length)
        let edit = TextEdit.difference(from: text, to: result as String, selection: caret..<caret)
        apply(edit, actionName: String(localized: "Replace All"))
        updateFindMatches()
    }

    /// The standard Find menu items, which AppKit sends as `performFindPanelAction(_:)`.
    func performFindAction(_ action: NSTextFinder.Action) {
        guard let proxy else { return }
        switch action {
        case .showFindInterface, .showReplaceInterface: proxy.showFind(replace: action == .showReplaceInterface)
        case .nextMatch, .previousMatch: findNext(backward: action == .previousMatch)
        case .replace, .replaceAndFind: replaceCurrentMatch()
        case .replaceAll, .replaceAllInSelection: replaceAllMatches()
        case .setSearchString: proxy.useSelectionForFind()
        case .hideFindInterface: proxy.hideFind()
        case .hideReplaceInterface: proxy.showsReplace = false
        case .selectAll, .selectAllInSelection: selectAllMatches()
        @unknown default: break
        }
    }

    private func selectAllMatches() {
        updateFindMatches()
        if !findMatches.isEmpty { textView.selectedRanges = findMatches.map { NSValue(range: $0) } }
    }

    // MARK: - Navigation

    var headings: [EditorProxy.Heading] {
        index.blocks.indices.compactMap { position in
            guard case .heading(let level) = index.blocks[position].kind else { return nil }
            let source = index.blocks[position].source
            let prefix = MarkdownSyntax.headingMarkers(in: source).prefix
            return EditorProxy.Heading(
                title: index.blocks[position].text, level: level,
                offset: index.sourceRange(of: position).lowerBound + min(prefix, source.utf16.count))
        }
    }

    func reveal(_ range: NSRange) {
        let length = (textView.string as NSString).length
        let clamped = NSRange(
            location: min(range.location, length), length: min(range.length, max(0, length - range.location)))
        focus()
        textView.setSelectedRange(clamped)
        textView.scrollRangeToVisible(clamped)
        if clamped.length > 0 { textView.showFindIndicator(for: clamped) }
    }

    /// Casts `spell` at the caret with nothing typed to remove.
    func castAtCaret(_ spell: Spell) {
        let caret = textView.selectedRange().location
        focus()
        cast(spell, trigger: caret..<caret)
    }
}
#endif
