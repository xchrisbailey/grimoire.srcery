#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct StreamingTests {
    static let sample = "# Potions\n\nInk of recall.\n"

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

    func waitUntilFinished(_ controller: EditorController) async {
        for _ in 0..<100 where controller.streaming?.isFinished != true && controller.streaming != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func streamsInThenKeepsAsOneUndo() async throws {
        let controller = makeEditor(Self.sample, height: 500)
        var reasons: [Version.Reason] = []
        controller.onBeforeLargeEdit = { reasons.append($0) }
        let end = (Self.sample as NSString).length
        controller.streamInsertion(
            stream(["\nThe ", "ink ", "dries."]), replacing: NSRange(location: end, length: 0), actionName: "Continue")
        await waitUntilFinished(controller)
        #expect(controller.text == Self.sample + "\nThe ink dries.")
        #expect(controller.streamingHint.isVisible)
        #expect(controller.handleKey(try keyEvent(36, "\r")))
        #expect(!controller.isStreaming)
        #expect(controller.text == Self.sample + "\nThe ink dries.")
        #expect(reasons == [.intelligence])
        controller.textView.undoManager?.undo()
        #expect(controller.text == Self.sample)
    }

    @Test func escapeDiscardsAndRestoresTheSelection() async throws {
        let controller = makeEditor(Self.sample, height: 500)
        let recall = (Self.sample as NSString).range(of: "Ink of recall.")
        controller.streamInsertion(stream(["Quill ", "of memory."]), replacing: recall, actionName: "Rewrite")
        await waitUntilFinished(controller)
        #expect(controller.text.contains("Quill of memory."))
        #expect(controller.handleKey(try keyEvent(53, "\u{1b}")))
        #expect(controller.text == Self.sample)
        #expect(controller.textView.undoManager?.canUndo == false)
    }

    @Test func typingKeepsAFinishedResponse() async throws {
        let controller = makeEditor(Self.sample, height: 500)
        controller.streamInsertion(stream(["!"]), replacing: NSRange(location: 2, length: 0), actionName: "Spell")
        await waitUntilFinished(controller)
        #expect(!controller.handleKey(try keyEvent(0, "a")))
        #expect(!controller.isStreaming)
        #expect(controller.text.hasPrefix("# !Potions"))
    }

    @Test func aFailedStreamLeavesTheTextAlone() async {
        let controller = makeEditor(Self.sample, height: 500)
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
