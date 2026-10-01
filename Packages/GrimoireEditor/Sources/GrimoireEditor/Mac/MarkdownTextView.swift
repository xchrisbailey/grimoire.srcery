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

    /// Drawn in the text's place while the view is empty.
    var placeholder: String? {
        didSet { if placeholder != oldValue, string.isEmpty { needsDisplay = true } }
    }
    var placeholderAttributes: [NSAttributedString.Key: Any] = [:]

    public override func draw(_ dirtyRect: NSRect) {
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
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let padding = textContainer?.lineFragmentPadding ?? 5
        let horizontal = max(24, (bounds.width - maxLineWidth - padding * 2) / 2)
        let inset = NSSize(width: horizontal.rounded(.down), height: verticalInset)
        if textContainerInset != inset { textContainerInset = inset }
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
