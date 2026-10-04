#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct BlockBehaviorTests {
    func editorAtEnd(_ text: String) -> EditorController {
        makeEditor(text, caret: (text as NSString).length)
    }

    @Test func enterContinuesAListAndUndoes() {
        let controller = editorAtEnd("- Mandrake")
        controller.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(controller.text == "- Mandrake\n- ")
        controller.type("Moonwater")
        #expect(controller.text == "- Mandrake\n- Moonwater")
        #expect(controller.index.blocks.map(\.kind) == [.listItem(.bullet), .listItem(.bullet)])
        controller.textView.undoManager?.undo()
        controller.textView.undoManager?.undo()
        #expect(controller.text == "- Mandrake")
    }

    @Test func tabAndBackspaceOnListItems() {
        let controller = editorAtEnd("- one\n- two")
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "- one\n  - two")
        controller.textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(controller.text == "- one\n- two")
        controller.textView.setSelectedRange(NSRange(location: 8, length: 0))
        controller.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(controller.text == "- one\n\ntwo")
    }

    @Test func typedShortcutsExpand() {
        let controller = editorAtEnd("")
        controller.type("[] ")
        #expect(controller.text == "- [ ] ")
        let code = editorAtEnd("Intro\n\n")
        code.type("```")
        #expect(code.text == "Intro\n\n```\n```")
    }

    @Test func movesAndDuplicatesBlocks() {
        let controller = makeEditor("# A\n\nB\n\nC\n", caret: 6)
        controller.textView.doCommand(by: #selector(NSResponder.moveParagraphBackwardAndModifySelection(_:)))
        #expect(controller.text == "B\n\n# A\n\nC\n")
        controller.moveBlock(0, to: 2)
        #expect(controller.text == "# A\n\nC\n\nB\n")
        controller.duplicateBlock(2)
        #expect(controller.text == "# A\n\nC\n\nB\n\nB\n")
        controller.convertBlock(1, to: .heading(level: 2))
        #expect(controller.text == "# A\n\n## C\n\nB\n\nB\n")
        controller.deleteBlock(3)
        #expect(controller.text == "# A\n\n## C\n\nB\n")
    }

    @Test func commandReturnTogglesTasksUndoably() throws {
        let controller = editorAtEnd("- [ ] Ember")
        #expect(controller.handleKey(try keyEvent(36, "\r", .command)))
        #expect(controller.text == "- [x] Ember")
        controller.textView.undoManager?.undo()
        #expect(controller.text == "- [ ] Ember")
    }

    @Test func escapeSelectsTheBlock() {
        let controller = makeEditor("Intro\n\n- Mandrake\n", caret: 10)
        controller.textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(controller.textView.selectedRange() == NSRange(location: 7, length: 10))
    }

    @Test func pastingAURLOverTextMakesALink() {
        let controller = editorAtEnd("See the docs")
        controller.textView.setSelectedRange(NSRange(location: 8, length: 4))
        let board = NSPasteboard(name: NSPasteboard.Name("grimoire-test-\(UUID())"))
        board.clearContents()
        board.setString("https://srcery.computer", forType: .string)
        #expect(controller.paste(from: board))
        #expect(controller.text == "See the [docs](https://srcery.computer)")
        board.releaseGlobally()
    }

    @Test func pastingAnImageSavesItInAssetsAndAsksForAltText() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "grimoire-paste-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = editorAtEnd("")
        controller.fileURL = folder.appending(path: "page.md")
        var casts: [IntelligenceCast] = []
        controller.intelligenceEnabled = true
        controller.onIntelligence = { casts.append($0) }
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let png = try #require(image?.representation(using: .png, properties: [:]))
        let board = NSPasteboard(name: NSPasteboard.Name("grimoire-test-\(UUID())"))
        board.clearContents()
        board.setData(png, forType: .png)
        #expect(controller.paste(from: board))
        board.releaseGlobally()
        #expect(controller.text.hasPrefix("![pasted-"))
        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "assets").path())
        #expect(saved.count == 1)
        #expect(controller.text.contains("(assets/\(saved[0]))"))
        #expect(casts.count == 1 && casts[0].command == "alt")
        #expect(FileManager.default.fileExists(atPath: casts[0].source))
    }

    @Test func richTextBecomesMarkdown() {
        let html = """
            <h1>Potions</h1><p>Some <b>bold</b>, <i>italic</i> and <a href="https://x.dev/docs">a link</a>.</p>
            <ul><li>one</li><li>two</li></ul>
            """
        let markdown = HTMLToMarkdown.convert(html: Data(html.utf8))
        #expect(markdown == "# Potions\n\nSome **bold**, _italic_ and [a link](https://x.dev/docs).\n\n- one\n- two")
    }
}
#endif
