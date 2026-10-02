#if os(macOS)
import AppKit

/// Raw mode's line numbers, drawn in the margin left of the text column.
extension MarkdownTextView {
    /// Adds or removes the view the numbers draw in, keeping it above the text.
    func updateLineNumberView() {
        if showsLineNumbers {
            let view = lineNumberView ?? LineNumberView(textView: self)
            view.frame = bounds
            addSubview(view, positioned: .above, relativeTo: nil)
            view.needsDisplay = true
            lineNumberView = view
        } else {
            lineNumberView?.removeFromSuperview()
            lineNumberView = nil
        }
    }

    var lineCount: Int { currentLineStarts().count }

    /// Room for the widest line number and a gap, or nothing when they're off.
    var lineNumberGutter: CGFloat {
        guard showsLineNumbers else { return 0 }
        let digits = String(repeating: "8", count: max(3, String(lineCount).count))
        return (digits as NSString).size(withAttributes: lineNumberAttributes).width + 18
    }

    private func currentLineStarts() -> [Int] {
        if let lineStarts { return lineStarts }
        let text = string.utf16
        var starts = [0]
        var offset = 0
        var previous: UInt16 = 0
        for unit in text {
            offset += 1
            // \r\n is one break; a lone \r or \n is one too.
            if unit == 10 || unit == 13 {
                if unit == 10, previous == 13 { starts[starts.count - 1] = offset } else { starts.append(offset) }
            }
            previous = unit
        }
        lineStarts = starts
        return starts
    }

    /// The 1-based line holding `offset`.
    private func lineNumber(at offset: Int) -> Int {
        let starts = currentLineStarts()
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low + 1
    }

    /// Each visible line's number, right-aligned against the text and on its first
    /// line's baseline.
    func drawLineNumbers(in dirtyRect: NSRect) {
        guard let layoutManager = textLayoutManager, let storage = textContentStorage else { return }
        let font = lineNumberAttributes[.font] as? NSFont ?? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let right = textContainerOrigin.x - 14
        let start = layoutManager.textViewportLayoutController.viewportRange?.location
            ?? storage.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: textContainerOrigin.y)
            if frame.minY > dirtyRect.maxY { return false }
            guard frame.maxY >= dirtyRect.minY, let line = fragment.textLineFragments.first else { return true }
            let offset = storage.offset(from: storage.documentRange.location, to: fragment.rangeInElement.location)
            let label = String(lineNumber(at: offset)) as NSString
            let size = label.size(withAttributes: lineNumberAttributes)
            let baseline = frame.minY + line.typographicBounds.minY + line.glyphOrigin.y
            label.draw(
                at: NSPoint(x: right - size.width, y: baseline - font.ascender), withAttributes: lineNumberAttributes)
            return true
        }
        // An empty last line has no fragment of its own.
        if (string as NSString).hasSuffix("\n"), let last = lastLineRect(), last.intersects(dirtyRect) {
            let label = String(lineCount) as NSString
            let size = label.size(withAttributes: lineNumberAttributes)
            let origin = NSPoint(x: right - size.width, y: last.midY - size.height / 2)
            label.draw(at: origin, withAttributes: lineNumberAttributes)
        }
    }

    /// The empty line after a final newline, where the caret sits at the end of the text.
    private func lastLineRect() -> CGRect? {
        guard let layoutManager = textLayoutManager, let storage = textContentStorage else { return nil }
        var lineFrame: CGRect?
        layoutManager.enumerateTextSegments(
            in: NSTextRange(location: storage.documentRange.endLocation), type: .standard, options: []
        ) { _, frame, _, _ in
            lineFrame = frame
            return false
        }
        return lineFrame?.offsetBy(dx: 0, dy: textContainerOrigin.y)
    }
}

/// A transparent view over the text view that only draws its line numbers and lets every
/// click through.
final class LineNumberView: NSView {
    private weak var textView: MarkdownTextView?

    init(textView: MarkdownTextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        textView?.drawLineNumbers(in: dirtyRect)
    }
}
#endif
