#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct StreamingTests {
    static let sample = "# Potions\n\nInk of recall.\n"

    func makeController() -> (EditorController, NSWindow) {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(Self.sample, flavor: .markdown)
        return (controller, window)
    }

    /// A stream that yields `pieces` as growing text.
    func stream(_ pieces: [String], failing: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            var text = ""
            for piece in pieces {
                text += piece
                continuation.yield(text)
            }
            if failing { continuation.finish(throwing: CocoaError(.featureUnsupported)) } else { continuation.finish() }
        }
    }

    func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func waitUntilFinished(_ controller: EditorController) async {
        for _ in 0..<100 where controller.streaming?.isFinished != true && controller.streaming != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func streamsInThenKeepsAsOneUndo() async {
        let (controller, window) = makeController()
        defer { withExtendedLifetime(window) {} }
        var reasons: [Version.Reason] = []
        controller.onBeforeLargeEdit = { reasons.append($0) }
        let end = (Self.sample as NSString).length
        controller.streamInsertion(
            stream(["\nThe ", "ink ", "dries."]), replacing: NSRange(location: end, length: 0), actionName: "Continue")
        await waitUntilFinished(controller)
        #expect(controller.text == Self.sample + "\nThe ink dries.")
        #expect(controller.streamingHint.isVisible)
        #expect(controller.handleKey(key(36, "\r")))
        #expect(!controller.isStreaming)
        #expect(controller.text == Self.sample + "\nThe ink dries.")
        #expect(reasons == [.intelligence])
        controller.textView.undoManager?.undo()
        #expect(controller.text == Self.sample)
    }

    @Test func escapeDiscardsAndRestoresTheSelection() async {
        let (controller, _) = makeController()
        let recall = (Self.sample as NSString).range(of: "Ink of recall.")
        controller.streamInsertion(stream(["Quill ", "of memory."]), replacing: recall, actionName: "Rewrite")
        await waitUntilFinished(controller)
        #expect(controller.text.contains("Quill of memory."))
        #expect(controller.handleKey(key(53, "\u{1b}")))
        #expect(controller.text == Self.sample)
        #expect(controller.textView.undoManager?.canUndo == false)
    }

    @Test func typingKeepsAFinishedResponse() async {
        let (controller, _) = makeController()
        controller.streamInsertion(stream(["!"]), replacing: NSRange(location: 2, length: 0), actionName: "Spell")
        await waitUntilFinished(controller)
        #expect(!controller.handleKey(key(0, "a")))
        #expect(!controller.isStreaming)
        #expect(controller.text.hasPrefix("# !Potions"))
    }

    @Test func aFailedStreamLeavesTheTextAlone() async {
        let (controller, _) = makeController()
        var failure: Error?
        controller.streamInsertion(
            stream(["half"], failing: true), replacing: NSRange(location: 0, length: 0), actionName: "Spell"
        ) { failure = $0 }
        for _ in 0..<100 where failure == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(failure != nil)
        #expect(controller.text == Self.sample)
        #expect(!controller.isStreaming)
    }
}
#endif
