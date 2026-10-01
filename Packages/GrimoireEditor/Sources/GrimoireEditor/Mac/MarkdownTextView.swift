#if os(macOS)
import AppKit

/// The editor's text view: TextKit 2, a centered column of readable width, clickable
/// checkboxes, and ⌘-click on links.
public final class MarkdownTextView: NSTextView {
    /// Called for a ⌘-click on a link, with the destination as written.
    var onOpenLink: ((String) -> Void)?
    /// Called for a click on a drawn checkbox, with the offset of the task's line.
    var onToggleTask: ((Int) -> Void)?
    /// Called for a ⌘-click away from links, with the clicked offset.
    var onSelectBlock: ((Int) -> Void)?
    /// Offered every key press first; returns true when it handled the key.
    var onKeyCommand: ((NSEvent) -> Bool)?
    /// Offered every paste first; returns true when it handled the pasteboard.
    var onPaste: ((NSPasteboard) -> Bool)?
    /// Follows the mouse over the text, for the block handle.
    var onMouseMoved: ((CGPoint) -> Void)?
    var onMouseExited: (() -> Void)?
    /// Called when the view switches between light and dark, with whether it's dark now.
    var onAppearanceChange: ((Bool) -> Void)?
    /// Drawn behind the caret's line (Raw mode); nil draws nothing.
    var caretLineColor: NSColor? {
        didSet { needsDisplay = true }
    }

    private var hoverArea: NSTrackingArea?

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExited?()
    }
    var maxLineWidth: CGFloat = 680 {
        didSet { updateInsets() }
    }
    var verticalInset: CGFloat = 30 {
        didSet { updateInsets() }
    }
    /// Extra room below the text, so typewriter scrolling can center the last line.
    var bottomOverscroll: CGFloat = 0 {
        didSet {
            guard bottomOverscroll != oldValue else { return }
            setFrameSize(NSSize(width: frame.width, height: frame.height - oldValue))
        }
    }

    /// Drawn in the text's place while the view is empty.
    var placeholder: String? {
        didSet { if placeholder != oldValue, string.isEmpty { needsDisplay = true } }
    }
    var placeholderAttributes: [NSAttributedString.Key: Any] = [:]

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?(isDarkAppearance)
    }

    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    public override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if caretLineColor != nil { needsDisplay = true }
    }

    public override func draw(_ dirtyRect: NSRect) {
        if let caretLineColor, selectedRange().length == 0, let line = caretLineRect() {
            caretLineColor.setFill()
            line.fill()
        }
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: placeholderAttributes)
    }

    public override func didChangeText() {
        super.didChangeText()
        // The placeholder comes and goes with the first character.
        if (string as NSString).length <= 1 { needsDisplay = true }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if bottomOverscroll > 0 { size.height = contentHeight(proposed: newSize.height) + bottomOverscroll }
        super.setFrameSize(size)
        updateInsets()
    }

    /// The height the text needs, without the overscroll.
    private func contentHeight(proposed: CGFloat) -> CGFloat {
        guard let layoutManager = textLayoutManager else { return proposed }
        let used = layoutManager.usageBoundsForTextContainer.height
        return max(used + textContainerInset.height * 2, enclosingScrollView?.contentSize.height ?? 0)
    }

    private func updateInsets() {
        let padding = textContainer?.lineFragmentPadding ?? 5
        let horizontal = max(24, (bounds.width - maxLineWidth - padding * 2) / 2)
        let inset = NSSize(width: horizontal.rounded(.down), height: verticalInset)
        if textContainerInset != inset { textContainerInset = inset }
    }

    /// The caret's line across the text column, in view coordinates.
    private func caretLineRect() -> CGRect? {
        guard let layoutManager = textLayoutManager, let storage = textContentStorage,
            let location = storage.location(storage.documentRange.location, offsetBy: selectedRange().location)
        else { return nil }
        var lineFrame: CGRect?
        let firstSegment: (NSTextRange?, CGRect, CGFloat, NSTextContainer) -> Bool = { _, frame, _, _ in
            lineFrame = frame
            return false
        }
        layoutManager.enumerateTextSegments(
            in: NSTextRange(location: location), type: .standard, options: [], using: firstSegment)
        guard let frame = lineFrame else { return nil }
        let padding = textContainer?.lineFragmentPadding ?? 5
        return CGRect(
            x: textContainerOrigin.x + padding - 6, y: textContainerOrigin.y + frame.minY,
            width: (textContainer?.size.width ?? bounds.width) - padding * 2 + 12, height: frame.height)
    }

    // MARK: - Clicks

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let offset = taskLine(at: point) {
            onToggleTask?(offset)
            return
        }
        if event.modifierFlags.contains(.command) {
            if let link = link(at: point) {
                onOpenLink?(link)
            } else {
                onSelectBlock?(characterIndexForInsertion(at: point))
            }
            return
        }
        super.mouseDown(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        if onKeyCommand?(event) == true { return }
        super.keyDown(with: event)
    }

    public override func paste(_ sender: Any?) {
        if onPaste?(NSPasteboard.general) == true { return }
        super.paste(sender)
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMouseMoved?(point)
        if taskLine(at: point) != nil || (event.modifierFlags.contains(.command) && link(at: point) != nil) {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if event.modifierFlags.contains(.command), link(at: point) != nil {
            NSCursor.pointingHand.set()
        }
    }

    /// The document offset of the task line whose drawn checkbox is under `point`.
    private func taskLine(at point: CGPoint) -> Int? {
        guard let layoutManager = textLayoutManager, let storage = textContentStorage else { return nil }
        let containerPoint = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: containerPoint) as? MarkdownLayoutFragment,
            case .task(_, let indent) = fragment.decoration.kind
        else { return nil }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let frame = fragment.layoutFragmentFrame
        let size = LineDecoration.checkboxSize
        let box = CGRect(
            x: padding + indent - 3, y: frame.minY + fragment.firstLineCenterY - size / 2 - 3,
            width: size + 6, height: size + 6)
        guard box.contains(containerPoint), let range = fragment.textElement?.elementRange else { return nil }
        return storage.offset(from: storage.documentRange.location, to: range.location)
    }

    private func link(at point: CGPoint) -> String? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        for candidate in [index, index - 1] where candidate >= 0 && candidate < textStorage.length {
            if let link = textStorage.attribute(.grimoireLink, at: candidate, effectiveRange: nil) as? String {
                return link
            }
        }
        return nil
    }
}
#endif
