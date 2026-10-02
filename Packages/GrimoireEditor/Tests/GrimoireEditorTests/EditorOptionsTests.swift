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

    /// Types as the keyboard does, so auto-pairing sees it.
    func typeKeys(_ string: String, into controller: EditorController) {
        for character in string {
            controller.textView.insertText(
                String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    @Test func bracketsAndBackticksPair() {
        let controller = makeController("", mode: .raw)
        typeKeys("(x", into: controller)
        #expect(controller.text == "(x)")
        typeKeys(")", into: controller)
        #expect(controller.text == "(x)")
        #expect(controller.textView.selectedRange().location == 3)
        typeKeys(" `code`", into: controller)
        #expect(controller.text == "(x) `code`")
    }

    @Test func threeBackticksStillMakeAFence() {
        let controller = makeController("", mode: .preview)
        typeKeys("```", into: controller)
        #expect(controller.text.hasPrefix("```"))
        #expect(!controller.text.hasPrefix("````"))
    }

    @Test func apostrophesDontPair() {
        let controller = makeController("", mode: .raw)
        typeKeys("don't", into: controller)
        #expect(controller.text == "don't")
    }

    @Test func markersWrapTheSelection() {
        let controller = makeController("make it bold", mode: .raw)
        controller.textView.setSelectedRange(NSRange(location: 8, length: 4))
        typeKeys("*", into: controller)
        typeKeys("*", into: controller)
        #expect(controller.text == "make it **bold**")
        #expect(controller.textView.selectedRange() == NSRange(location: 10, length: 4))
    }

    @Test func backspaceRemovesAnEmptyPair() {
        let controller = makeController("", mode: .raw)
        typeKeys("[", into: controller)
        #expect(controller.text == "[]")
        controller.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(controller.text == "")
    }

    @Test func pairingCanBeTurnedOff() {
        let controller = makeController("", mode: .raw)
        controller.autoPairs = false
        typeKeys("(", into: controller)
        #expect(controller.text == "(")
    }

    @Test func listShortcutsStillWork() {
        let controller = makeController("", mode: .preview)
        typeKeys("[] ", into: controller)
        #expect(controller.text == "- [ ] ")
    }

    @Test func sentenceFocusFindsTheCaretsSentence() {
        let text = "First one here. Second one there. Third."
        let block = NSRange(location: 0, length: (text as NSString).length)
        let second = Sentences.range(around: 20, in: block, of: text)
        #expect(second.map { (text as NSString).substring(with: $0).hasPrefix("Second one there.") } == true)
        let first = Sentences.range(around: 3, in: block, of: text)
        #expect(first?.location == 0)
    }

    @Test func partsOfSpeechColorWordsButNotCode() {
        let controller = makeController("Ravens fly quickly over `dark` hills.", mode: .preview, caret: 0)
        var theme = controller.theme
        theme.partsOfSpeech = Set(PartOfSpeech.allCases)
        controller.theme = theme
        let storage = controller.textView.textStorage!
        func color(at offset: Int) -> PaletteColor? {
            guard let color = storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
            else { return nil }
            var resolved: NSColor?
            controller.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.sRGB)
            }
            guard let resolved else { return nil }
            return PaletteColor(
                red: UInt8((resolved.redComponent * 255).rounded()),
                green: UInt8((resolved.greenComponent * 255).rounded()),
                blue: UInt8((resolved.blueComponent * 255).rounded()))
        }
        let palette = controller.styler.theme.current.palette
        let text = controller.text as NSString
        #expect(color(at: text.range(of: "fly").location) == palette.link)
        #expect(color(at: text.range(of: "quickly").location) == palette.magic)
        #expect(color(at: text.range(of: "dark").location) != palette.caret)
    }
}
#endif
