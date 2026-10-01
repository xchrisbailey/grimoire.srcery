#if os(macOS)
import AppKit
import GrimoireCore
import Observation

/// A handle the window keeps on its editor: find and replace, the heading outline, casting
/// spells from Incantations, and jumping to a match from project search.
@MainActor @Observable
public final class EditorProxy {
    // MARK: Find

    public var findQuery = "" {
        didSet { if findQuery != oldValue { controller?.updateFindMatches() } }
    }
    public var replacement = ""
    public var caseSensitive = false {
        didSet { if caseSensitive != oldValue { controller?.updateFindMatches() } }
    }
    public var regex = false {
        didSet { if regex != oldValue { controller?.updateFindMatches() } }
    }
    public var wholeWord = false {
        didSet { if wholeWord != oldValue { controller?.updateFindMatches() } }
    }
    public internal(set) var isFindVisible = false
    public internal(set) var showsReplace = false
    /// How many matches the query has, and which one is selected (nil when none is).
    public internal(set) var matchCount = 0
    public internal(set) var currentMatch: Int?
    /// Bumped to ask the find bar to focus its search field.
    public internal(set) var findFocusRequest = 0

    public var search: TextSearch {
        TextSearch(findQuery, caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)
    }

    @ObservationIgnored weak var controller: EditorController?

    public init() {}

    /// Shows the find bar, seeded with the selection when it's a short single line.
    public func showFind(replace: Bool = false) {
        if let selected = controller?.selectedText, !selected.isEmpty, selected.count < 200, !selected.contains("\n") {
            findQuery = selected
        }
        isFindVisible = true
        showsReplace = showsReplace || replace
        findFocusRequest += 1
        controller?.updateFindMatches()
    }

    public func hideFind() {
        isFindVisible = false
        controller?.updateFindMatches()
        controller?.focus()
    }

    public func findNext() { controller?.findNext(backward: false) }
    public func findPrevious() { controller?.findNext(backward: true) }
    public func replaceCurrent() { controller?.replaceCurrentMatch() }
    public func replaceAll() { controller?.replaceAllMatches() }

    /// Uses the selection as the search text without showing the bar (⌘E).
    public func useSelectionForFind() {
        guard let selected = controller?.selectedText, !selected.isEmpty else { return }
        findQuery = selected
    }

    // MARK: Navigation

    /// The open document's headings, in order.
    public var headings: [Heading] { controller?.headings ?? [] }

    /// Selects `range` in the document, scrolls to it and puts the focus in the editor.
    public func reveal(_ range: NSRange) {
        controller?.reveal(range)
    }

    /// Casts a spell at the caret, as if it were chosen from the Spells menu.
    public func cast(_ spell: Spell) {
        controller?.castAtCaret(spell)
    }

    public var hasEditor: Bool { controller != nil }

    /// The selected text, empty when nothing is selected.
    public var selectedText: String { controller?.selectedText ?? "" }

    /// Replaces the whole text as one undoable edit, keeping the caret near where it was.
    public func replaceText(_ text: String, actionName: String) {
        guard let controller else { return }
        let caret = min(controller.textView.selectedRange().location, (text as NSString).length)
        controller.apply(
            TextEdit.difference(from: controller.text, to: text, selection: caret..<caret), actionName: actionName)
    }

    /// Streams a model's response in place of the selection (or at the caret). See
    /// `EditorController.streamInsertion`.
    public func streamIntoSelection(
        _ stream: AsyncThrowingStream<String, Error>, actionName: String, onError: @escaping (Error) -> Void = { _ in }
    ) {
        guard let controller else { return }
        controller.focus()
        controller.streamInsertion(
            stream, replacing: controller.textView.selectedRange(), actionName: actionName, onError: onError)
    }

    /// Streams a model's response in place of `range`.
    public func stream(
        _ stream: AsyncThrowingStream<String, Error>, replacing range: NSRange, actionName: String,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        controller?.focus()
        controller?.streamInsertion(stream, replacing: range, actionName: actionName, onError: onError)
    }

    public var isStreaming: Bool { controller?.isStreaming ?? false }

    /// Puts the keyboard focus in the editor.
    public func focusEditor() {
        controller?.focus()
    }

    public struct Heading: Identifiable, Hashable, Sendable {
        public var title: String
        public var level: Int
        /// Where the heading's text starts.
        public var offset: Int
        public var id: Int { offset }
    }
}
#endif
