#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct EditorControllerTests {
    static let sample = """
        # Potion ledger

        Brews from the **autumn** batch, see [runes](runes.md).

        - [ ] Ember draught
        - [x] Moonwater tincture

        > Keep the volatile ones up high.

        ```swift
        let brew = "ink"
        ```

        """

    func makeController(_ text: String = sample) -> EditorController {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.load(text, flavor: .markdown)
        return controller
    }

    func font(_ controller: EditorController, at offset: Int) -> NSFont? {
        controller.textView.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
    }

    @Test func stylesWithoutChangingTheText() {
        let controller = makeController()
        #expect(controller.text == Self.sample)
        // The caret starts in the heading, so its marker is dimmed, not hidden.
        #expect(font(controller, at: 2)?.pointSize == 34)
        let bold = (Self.sample as NSString).range(of: "autumn").location
        #expect(font(controller, at: bold)?.pointSize == 15.5)
        // Markers outside the caret's block shrink to nothing.
        #expect(font(controller, at: bold - 1)?.pointSize ?? 99 < 1)
        let code = (Self.sample as NSString).range(of: "let brew").location
        let decoration = controller.textView.textStorage?.attribute(.grimoireDecoration, at: code, effectiveRange: nil)
        #expect((decoration as? LineDecoration)?.kind == .code(.middle))
    }

    @Test func movingTheCaretRevealsMarkers() {
        let controller = makeController()
        let bold = (Self.sample as NSString).range(of: "autumn").location
        controller.textView.setSelectedRange(NSRange(location: bold, length: 0))
        #expect(font(controller, at: bold - 1)?.pointSize == 15.5)
        #expect(font(controller, at: 0)?.pointSize ?? 99 < 1)
    }

    @Test func typingUpdatesTheBindingAndOnlyTheTouchedLine() {
        let controller = makeController()
        var received = ""
        controller.onTextChange = { received = $0 }
        let offset = (Self.sample as NSString).range(of: "batch").location
        controller.textView.setSelectedRange(NSRange(location: offset, length: 0))
        controller.textView.insertText("big ", replacementRange: controller.textView.selectedRange())
        #expect(received == Self.sample.replacingOccurrences(of: "batch", with: "big batch"))
        let before = Self.sample.split(separator: "\n", omittingEmptySubsequences: false)
        let after = received.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(before.count == after.count)
        #expect(zip(before, after).filter { $0 != $1 }.count == 1)
        #expect(controller.index.document.markdown == received)
    }

    @Test func typingAHeadingMarkerRestyles() {
        let controller = makeController("Plain\n")
        controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.textView.insertText("## ", replacementRange: controller.textView.selectedRange())
        #expect(controller.index.blocks.first?.kind == .heading(level: 2))
        #expect(font(controller, at: 4)?.pointSize == 20)
    }

    @Test func togglesTasksUndoably() {
        let controller = makeController()
        let task = (Self.sample as NSString).range(of: "- [ ] Ember").location
        controller.toggleTask(at: task)
        #expect(controller.text.contains("- [x] Ember draught"))
        controller.textView.undoManager?.undo()
        #expect(controller.text.contains("- [ ] Ember draught"))
    }

    @Test func linksToMarkdownOpenInTheEditor() {
        var opened: URL?
        let file = URL(filePath: "/notes/potions.md")
        MarkdownEditor.open("runes.md#sigils", from: file) { opened = $0 }
        #expect(opened?.path() == "/notes/runes.md")
        MarkdownEditor.open("../lore/moon%20calendar.md", from: file) { opened = $0 }
        #expect(opened?.path(percentEncoded: false) == "/lore/moon calendar.md")
    }

    /// The "done when" for #6: typing in a ~10k-line document stays well inside a frame.
    @Test func typingInALargeDocumentIsQuick() {
        var text = ""
        var line = 0
        while line < 10_000 {
            text +=
                "## Section \(line)\n\nSome **bold** text with `code` and a [link](x.md).\n\n- item one\n- item two\n\n"
            line += 7
        }
        // Host the editor in a window, so TextKit lays out only what's visible, as in the app.
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(text, flavor: .markdown)
        window.displayIfNeeded()
        let middle = (text as NSString).length / 2
        let paragraph = (text as NSString).range(of: "Some", range: NSRange(location: middle, length: 2000)).location
        controller.textView.setSelectedRange(NSRange(location: paragraph, length: 0))
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for _ in 0..<30 {
            let elapsed = clock.measure {
                controller.textView.insertText("x", replacementRange: controller.textView.selectedRange())
            }
            slowest = max(slowest, elapsed)
        }
        #expect(controller.index.document.markdown == controller.text)
        #if DEBUG
        #expect(slowest < .milliseconds(50))
        #else
        #expect(slowest < .milliseconds(16))
        #endif
        print("Slowest keystroke in a \(line)-line document: \(slowest)")
    }
}
#endif
