#if os(macOS)
import AppKit
import GrimoireCore

/// A model's response streaming into the text: tinted while it arrives and until it's kept,
/// one undo step once kept, and gone again if discarded.
struct StreamingInsertion {
    /// What the response replaces, where it was when streaming began.
    var originalRange: NSRange
    var originalText: String
    /// Where the response sits now.
    var insertedRange: NSRange
    var actionName: String
    var task: Task<Void, Never>?
    var isFinished = false
}

extension EditorController {
    /// Streams `stream`'s text (the whole response so far, each time) in place of `range`.
    /// When it finishes, ↩ keeps it as one undoable edit and esc removes it; typing on keeps it.
    public func streamInsertion(
        _ stream: AsyncThrowingStream<String, Error>, replacing range: NSRange, actionName: String,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        if streaming != nil { keepStreamedText() }
        let text = textView.string as NSString
        let range = NSRange(
            location: min(range.location, text.length), length: min(range.length, text.length - range.location))
        onBeforeLargeEdit?(.intelligence)
        streaming = StreamingInsertion(
            originalRange: range, originalText: text.substring(with: range), insertedRange: range,
            actionName: actionName)
        streamingHint.update()
        streaming?.task = Task { @MainActor [weak self] in
            do {
                for try await response in stream {
                    guard let self, self.streaming != nil else { return }
                    self.showStreamed(response)
                }
                self?.finishStreaming()
            } catch {
                self?.discardStreamedText()
                onError(error)
            }
        }
    }

    public var isStreaming: Bool { streaming != nil }

    /// True once a response has finished arriving and waits to be kept or discarded.
    public var isAwaitingKeep: Bool { streaming?.isFinished == true }

    /// Replaces what's streamed so far, without touching the undo history.
    private func showStreamed(_ response: String) {
        guard let current = streaming else { return }
        replaceWithoutUndo(current.insertedRange, with: response)
        streaming?.insertedRange = NSRange(location: current.insertedRange.location, length: response.utf16.count)
        tintStreamedText()
        let end = NSMaxRange(streaming?.insertedRange ?? current.insertedRange)
        isApplying = true
        textView.setSelectedRange(NSRange(location: end, length: 0))
        isApplying = false
        textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        streamingHint.update()
    }

    private func finishStreaming() {
        guard streaming != nil else { return }
        streaming?.isFinished = true
        streaming?.task = nil
        if streaming?.insertedRange.length == 0 {
            discardStreamedText()
        } else {
            streamingHint.update()
        }
    }

    /// Keeps the response as one undoable edit.
    public func keepStreamedText() {
        guard let current = streaming else { return }
        current.task?.cancel()
        streaming = nil
        clearStreamingTint()
        let response = (textView.string as NSString).substring(with: current.insertedRange)
        // Put the original back quietly, then make the whole change once, with undo.
        replaceWithoutUndo(current.insertedRange, with: current.originalText)
        let start = current.originalRange.location
        let end = start + response.utf16.count
        apply(
            TextEdit(
                range: start..<(start + current.originalText.utf16.count), replacement: response, selection: end..<end),
            actionName: current.actionName)
        streamingHint.update()
    }

    /// Stops the response and puts back what it replaced.
    public func discardStreamedText() {
        guard let current = streaming else { return }
        current.task?.cancel()
        streaming = nil
        clearStreamingTint()
        replaceWithoutUndo(current.insertedRange, with: current.originalText)
        textView.setSelectedRange(
            NSRange(location: current.originalRange.location + current.originalText.utf16.count, length: 0))
        streamingHint.update()
    }

    /// Keys while a response is showing: esc discards, ↩ keeps a finished one, other typing
    /// keeps it and carries on. Returns true when the key was used up.
    func handleStreamingKey(_ event: NSEvent) -> Bool {
        guard let current = streaming else { return false }
        if event.keyCode == 53 {
            discardStreamedText()
            return true
        }
        guard current.isFinished else { return true }
        if event.keyCode == 36 || event.keyCode == 76 {
            keepStreamedText()
            return true
        }
        keepStreamedText()
        return false
    }

    /// Clicking elsewhere keeps a finished response.
    func keepStreamedTextOnClick() {
        if streaming?.isFinished == true, !isApplying, NSApp.currentEvent?.type == .leftMouseDown {
            keepStreamedText()
        }
    }

    private func replaceWithoutUndo(_ range: NSRange, with text: String) {
        let undo = textView.undoManager
        undo?.disableUndoRegistration()
        isApplying = true
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.textStorage?.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
        isApplying = false
        undo?.enableUndoRegistration()
    }

    private func tintStreamedText() {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage,
            let range = streaming?.insertedRange
        else { return }
        layoutManager.removeRenderingAttribute(.underlineStyle, for: storage.documentRange)
        guard let start = storage.location(storage.documentRange.location, offsetBy: range.location),
            let end = storage.location(start, offsetBy: range.length),
            let textRange = NSTextRange(location: start, end: end)
        else { return }
        layoutManager.addRenderingAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, for: textRange)
        layoutManager.addRenderingAttribute(.underlineColor, value: styler.theme.magic, for: textRange)
    }

    private func clearStreamingTint() {
        guard let layoutManager = textView.textLayoutManager, let storage = textView.textContentStorage else { return }
        layoutManager.removeRenderingAttribute(.underlineStyle, for: storage.documentRange)
        layoutManager.removeRenderingAttribute(.underlineColor, for: storage.documentRange)
    }
}

/// The quiet line under a streaming response: "esc to stop" while it arrives, then "↩ keep ·
/// esc discard".
@MainActor
final class StreamingHint {
    private weak var controller: EditorController?
    private let label = NSTextField(labelWithString: "")

    init(controller: EditorController) {
        self.controller = controller
        label.isHidden = true
        label.isBordered = false
        label.drawsBackground = true
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        controller.textView.addSubview(label)
    }

    func update() {
        guard let controller, let streaming = controller.streaming else {
            label.isHidden = true
            return
        }
        let theme = controller.styler.theme
        let text =
            streaming.isFinished
            ? String(localized: "↩ keep · esc discard") : String(localized: "Writing… esc to stop")
        label.attributedStringValue = NSAttributedString(
            string: " " + text + " ", attributes: [.font: theme.metadata, .foregroundColor: theme.faint])
        label.backgroundColor = theme.codeBackground
        label.sizeToFit()
        let end = NSRange(location: NSMaxRange(streaming.insertedRange), length: 0)
        let screen = controller.textView.firstRect(forCharacterRange: end, actualRange: nil)
        guard let window = controller.textView.window else {
            label.isHidden = true
            return
        }
        let inWindow = window.convertFromScreen(screen)
        let point = controller.textView.convert(inWindow.origin, from: nil)
        label.setFrameOrigin(CGPoint(x: max(point.x, controller.textView.textContainerOrigin.x), y: point.y + 6))
        label.isHidden = false
    }

    var isVisible: Bool { !label.isHidden }
    var text: String { label.stringValue.trimmingCharacters(in: .whitespaces) }
}
#endif
