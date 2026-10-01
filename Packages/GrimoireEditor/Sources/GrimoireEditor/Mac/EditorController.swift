#if os(macOS)
import AppKit
import GrimoireCore

/// Keeps a `MarkdownTextView` and a `BlockIndex` in step: every edit updates the index
/// for the blocks around it and restyles just those, and moving the caret reveals the
/// markers of the block it lands in.
@MainActor
public final class EditorController: NSObject {
    public let textView: MarkdownTextView
    public let scrollView: NSScrollView
    public private(set) var index: BlockIndex
    public let styler: MarkdownStyler

    /// Called after the user changes the text.
    var onTextChange: ((String) -> Void)?
    /// Called for a ⌘-clicked link.
    var onOpenLink: ((String) -> Void)?
    /// Offered Escape before the editor uses it to select the block; returns true when it
    /// handled it (focus mode uses it to wake).
    var onEscape: (() -> Bool)?

    /// Focus mode: everything but the caret's block fades back.
    public var dimsAroundCaret = false {
        didSet {
            guard dimsAroundCaret != oldValue else { return }
            updateDimming()
        }
    }
    var litBlock: Int?

    /// The file being edited.
    var fileURL: URL?
    /// The text last sent to or received from the owner, to tell its updates from ours.
    var lastText: String = ""
    private var revealed: Int?
    private var isLoading = false
    var pendingShortcut = false
    /// Where a `/` was just typed, to check whether it opens the Spells menu.
    var pendingSlash: Int?
    /// The open Spells menu, if any.
    var spellSession: SpellSession?
    private(set) lazy var spellsMenu = SpellsMenu()
    /// Where recently cast spells are remembered.
    public var defaults = UserDefaults.standard
    private(set) lazy var blockHandle = BlockHandle(controller: self)
    var isApplying = false
    /// Each editor keeps its own undo history, so it belongs to the open file.
    private let undoManager = UndoManager()

    public init(theme: EditorTheme = EditorTheme()) {
        styler = MarkdownStyler(theme: theme)
        index = BlockIndex(text: "")

        let textView = MarkdownTextView(usingTextLayoutManager: true)
        self.textView = textView
        scrollView = NSScrollView()
        super.init()

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        applyChrome(theme)
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.textLayoutManager?.delegate = self
        textView.onToggleTask = { [weak self] offset in self?.toggleTask(at: offset) }
        textView.onOpenLink = { [weak self] link in self?.onOpenLink?(link) }
        textView.onSelectBlock = { [weak self] offset in self?.selectBlock(at: offset) }
        textView.onKeyCommand = { [weak self] event in self?.handleKey(event) ?? false }
        textView.onPaste = { [weak self] pasteboard in self?.paste(from: pasteboard) ?? false }
        textView.onMouseMoved = { [weak self] point in
            guard let self, self.mode == .preview else { return }
            self.blockHandle.mouseMoved(to: point)
        }
        textView.onMouseExited = { [weak self] in self?.blockHandle.hide() }
        textView.onAppearanceChange = { [weak self] isDark in self?.appearanceChanged(isDark: isDark) }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        styler.onImageLoaded = { [weak self] url in self?.restyleImages(showing: url) }
    }

    public var text: String { textView.string }

    /// The look: the light and dark themes and the editor's sizes. Setting a different one
    /// restyles the text in place.
    public var theme: EditorTheme {
        get { styler.theme }
        set {
            var theme = newValue
            theme.isDark = styler.theme.isDark
            guard theme != styler.theme else { return }
            styler.theme = theme
            styler.cellWidths.removeAll()
            applyChrome(theme)
            blockHandle.applyTheme(theme)
            restyleAll()
            if dimsAroundCaret {
                litBlock = nil
                updateDimming()
            }
        }
    }

    /// The text view's own colors: caret, selection, typing and the placeholder.
    private func applyChrome(_ theme: EditorTheme) {
        textView.insertionPointColor = theme.insertionPoint
        textView.selectedTextAttributes = [.backgroundColor: theme.selection]
        textView.typingAttributes = [.font: theme.body, .foregroundColor: theme.ink]
        textView.maxLineWidth = theme.maxLineWidth
        textView.placeholderAttributes = [.font: theme.body, .foregroundColor: theme.faint]
        textView.caretLineColor = mode == .raw ? theme.lineHighlight : nil
    }

    /// Light and dark themes can set different font styles, so the text is restyled when
    /// the appearance flips. Colors follow by themselves.
    private func appearanceChanged(isDark: Bool) {
        guard styler.theme.isDark != isDark else { return }
        styler.theme.isDark = isDark
        restyleAll()
    }

    /// Preview or Raw. Switching restyles the same text in place: no reload, the undo
    /// history stays, and the caret's line stays where it was on screen.
    public var mode: EditorMode {
        get { styler.mode }
        set {
            guard newValue != styler.mode else { return }
            let anchor = caretScreenOffset()
            styler.mode = newValue
            textView.caretLineColor = newValue == .raw ? styler.theme.lineHighlight : nil
            closeSpells()
            blockHandle.hide()
            restyleAll()
            if let anchor { restoreCaretScreenOffset(anchor) }
        }
    }

    /// How far the caret's line sits below the top of the visible area.
    private func caretScreenOffset() -> CGFloat? {
        guard let frame = caretLineFrame() else { return nil }
        return frame.minY - scrollView.contentView.bounds.minY
    }

    private func restoreCaretScreenOffset(_ offset: CGFloat) {
        guard let frame = caretLineFrame() else { return }
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: min(max(0, frame.minY - offset), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The caret line's layout fragment, in the text view's coordinates.
    private func caretLineFrame() -> CGRect? {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage,
            let location = storage.location(storage.documentRange.location, offsetBy: textView.selectedRange().location)
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.offsetBy(
            dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    /// Replaces the whole text (opening a file, or a reload from disk). Clears undo.
    public func load(_ text: String, flavor: DocumentFlavor) {
        isLoading = true
        lastText = text
        textView.caretLineColor = mode == .raw ? styler.theme.lineHighlight : nil
        textView.string = text
        index = BlockIndex(text: text, flavor: flavor)
        revealed = caretBlock()
        restyle(0..<index.blocks.count, all: true)
        textView.undoManager?.removeAllActions()
        isLoading = false
    }

    /// Takes new text from the owner while keeping the caret near where it was.
    public func replaceText(_ text: String, flavor: DocumentFlavor) {
        let selection = textView.selectedRange()
        load(text, flavor: flavor)
        let location = min(selection.location, (text as NSString).length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    // MARK: - Styling

    /// Restyles everything, for example after the file moved and relative images resolve
    /// somewhere new.
    public func restyleAll() {
        restyle(0..<index.blocks.count, all: true)
    }

    private func restyle(_ blocks: Range<Int>, all: Bool = false) {
        guard let storage = textView.textStorage else { return }
        styler.caret = textView.selectedRange().location
        storage.beginEditing()
        if all {
            styler.styleAll(storage, index: index, revealing: revealed)
        } else {
            styler.style(storage, index: index, blocks: blocks, revealing: revealed)
        }
        storage.endEditing()
    }

    private func caretBlock() -> Int? {
        index.blockIndex(at: textView.selectedRange().location)
    }

    private func restyleImages(showing url: URL) {
        for (position, block) in index.blocks.enumerated() where block.kind == .image {
            restyle(position..<(position + 1))
        }
    }

    // MARK: - Focus

    /// Fades every block but the caret's with a rendering attribute, which changes how text
    /// draws without touching the text storage.
    func updateDimming() {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage else { return }
        let block = dimsAroundCaret ? index.blockIndex(at: textView.selectedRange().location) : nil
        guard block != litBlock || !dimsAroundCaret else { return }
        litBlock = block
        let documentRange = storage.documentRange
        layoutManager.removeRenderingAttribute(.foregroundColor, for: documentRange)
        guard dimsAroundCaret else { return }
        let dim = styler.theme.marker
        let lit = block.map { NSRange(index.sourceRange(of: $0)) }
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

    // MARK: - Tasks

    /// Flips the checkbox on the task line starting at `offset`, as an undoable edit.
    func toggleTask(at offset: Int) {
        let text = textView.string as NSString
        let line = text.lineRange(for: NSRange(location: offset, length: 0))
        let selection = textView.selectedRange()
        guard
            let edit = BlockEditing.toggleTask(
                onLine: line, in: text, selection: selection.location..<NSMaxRange(selection))
        else { return }
        apply(edit, actionName: String(localized: "Toggle Task"))
    }
}

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
        let items = tableMenuItems(at: charIndex)
        for (position, item) in items.enumerated() { menu.insertItem(item, at: position) }
        return menu
    }

    public func textDidChange(_ notification: Notification) {
        blockHandle.hide()
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
        onTextChange?(text)
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

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        handleCommand(selector)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        if dimsAroundCaret { updateDimming() }
        if spellSession != nil, !isApplying { closeSpellsIfCaretLeft() }
        guard mode == .preview else { return }
        let block = caretBlock()
        if let previous = revealed, previous != block, previous < index.blocks.count,
            index.blocks[previous].kind == .table, !isApplying
        {
            // Leaving a table tidies its pipes, once the selection change has finished.
            let table = index.blocks[previous].id
            DispatchQueue.main.async { [weak self] in self?.formatTable(id: table) }
        }
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
