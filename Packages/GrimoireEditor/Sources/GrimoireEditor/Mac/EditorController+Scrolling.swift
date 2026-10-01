#if os(macOS)
import AppKit
import GrimoireCore

/// Keeping the caret's line in view: where it sits on screen when the mode changes, and in
/// the middle of the view for typewriter scrolling.
extension EditorController {
    /// Scrolls so the caret's line sits in the middle of the view, for typewriter scrolling.
    func centerCaret() {
        guard typewriterScrolling, let frame = caretLineFrame() else { return }
        let clip = scrollView.contentView
        textView.bottomOverscroll = clip.bounds.height / 2
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: min(max(0, frame.midY - clip.bounds.height / 2), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// How far the caret's line sits below the top of the visible area.
    func caretScreenOffset() -> CGFloat? {
        guard let frame = caretLineFrame() else { return nil }
        return frame.minY - scrollView.contentView.bounds.minY
    }

    func restoreCaretScreenOffset(_ offset: CGFloat) {
        guard let frame = caretLineFrame() else { return }
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: min(max(0, frame.minY - offset), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The caret line's layout fragment, in the text view's coordinates.
    func caretLineFrame() -> CGRect? {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage,
            let location = storage.location(storage.documentRange.location, offsetBy: textView.selectedRange().location)
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.offsetBy(
            dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }
}
#endif
