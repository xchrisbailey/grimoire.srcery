#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

/// Settings that change how the editor types and draws: tab width, spaces or tabs, line
/// numbers and the editor's own shortcuts.
@MainActor @Suite(.serialized) struct EditorOptionsTests {
    func makeController(_ text: String, mode: EditorMode = .raw, caret: Int? = nil) -> EditorController {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        controller.textView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.mode = mode
        controller.load(text, flavor: .markdown)
        controller.textView.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return controller
    }

    func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func tabTypesSpacesToTheNextStop() {
        let controller = makeController("ab")
        var theme = controller.theme
        theme.tabWidth = 4
        controller.theme = theme
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab  ")
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab      ")
    }

    @Test func tabTypesATabWhenTabsArePreferred() {
        let controller = makeController("ab")
        controller.indentsWithTabs = true
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab\t")
    }

    @Test func tabStopsFollowTheTabWidth() {
        let controller = makeController("\tx")
        var theme = controller.theme
        theme.tabWidth = 2
        controller.theme = theme
        let style = controller.textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        let interval = (style as? NSParagraphStyle)?.defaultTabInterval ?? 0
        #expect(abs(interval - theme.tabInterval) < 0.01)
        #expect(interval > 0)
    }

    @Test func lineNumbersShowOnlyInRaw() {
        let controller = makeController("one\ntwo", mode: .preview)
        controller.showsLineNumbers = true
        #expect(!controller.textView.showsLineNumbers)
        controller.mode = .raw
        #expect(controller.textView.showsLineNumbers)
        // The margin grows to fit the numbers.
        #expect(controller.textView.textContainerInset.width >= 24 + controller.textView.lineNumberGutter)
    }

    @Test func remappedShortcutsReplaceTheDefaults() throws {
        let controller = makeController("- [ ] Ember", mode: .preview)
        controller.keyBindings.toggleTask = KeyCombo("t", [.control, .command])
        #expect(!controller.handleKey(try key(36, "\r", .command)))
        #expect(controller.text == "- [ ] Ember")
        #expect(controller.handleKey(try key(17, "t", [.control, .command])))
        #expect(controller.text == "- [x] Ember")
    }

    @Test func readsKeyPressesAsCombos() throws {
        #expect(KeyCombo(event: try key(2, "D", [.command, .shift])) == KeyCombo("d", [.shift, .command]))
        #expect(KeyCombo(event: try key(76, "\u{3}", .command)) == KeyCombo(.return))
        #expect(KeyCombo(event: try key(53, "\u{1b}", [])) == KeyCombo(.escape, []))
    }
}
#endif
