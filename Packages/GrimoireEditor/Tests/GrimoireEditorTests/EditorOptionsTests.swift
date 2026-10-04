#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

/// Settings that change how the editor types and draws: tab width, spaces or tabs, line
/// numbers and the editor's own shortcuts.
@MainActor @Suite(.serialized) struct EditorOptionsTests {
    @Test func tabTypesSpacesToTheNextStop() {
        let controller = makeEditor("ab", mode: .raw, caret: 2)
        var theme = controller.theme
        theme.tabWidth = 4
        controller.theme = theme
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab  ")
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab      ")
    }

    @Test func tabTypesATabWhenTabsArePreferred() {
        let controller = makeEditor("ab", mode: .raw, caret: 2)
        controller.indentsWithTabs = true
        controller.textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "ab\t")
    }

    @Test func tabStopsFollowTheTabWidth() {
        let controller = makeEditor("\tx", mode: .raw, caret: 2)
        var theme = controller.theme
        theme.tabWidth = 2
        controller.theme = theme
        let style = controller.textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        let interval = (style as? NSParagraphStyle)?.defaultTabInterval ?? 0
        #expect(abs(interval - theme.tabInterval) < 0.01)
        #expect(interval > 0)
    }

    @Test func lineNumbersShowOnlyInRaw() {
        let controller = makeEditor("one\ntwo", mode: .preview, caret: 7)
        controller.showsLineNumbers = true
        #expect(!controller.textView.showsLineNumbers)
        controller.mode = .raw
        #expect(controller.textView.showsLineNumbers)
        // The margin grows to fit the numbers.
        #expect(controller.textView.textContainerInset.width >= 24 + controller.textView.lineNumberGutter)
    }

    @Test func remappedShortcutsReplaceTheDefaults() throws {
        let controller = makeEditor("- [ ] Ember", mode: .preview, caret: 11)
        controller.keyBindings.toggleTask = KeyCombo("t", [.control, .command])
        #expect(!controller.handleKey(try keyEvent(36, "\r", .command)))
        #expect(controller.text == "- [ ] Ember")
        #expect(controller.handleKey(try keyEvent(17, "t", [.control, .command])))
        #expect(controller.text == "- [x] Ember")
    }

    @Test func readsKeyPressesAsCombos() throws {
        #expect(KeyCombo(event: try keyEvent(2, "D", [.command, .shift])) == KeyCombo("d", [.shift, .command]))
        #expect(KeyCombo(event: try keyEvent(76, "\u{3}", .command)) == KeyCombo(.return))
        #expect(KeyCombo(event: try keyEvent(53, "\u{1b}", [])) == KeyCombo(.escape, []))
    }

    @Test func bracketsAndBackticksPair() {
        let controller = makeEditor("", mode: .raw)
        controller.typeKeys("(x")
        #expect(controller.text == "(x)")
        controller.typeKeys(")")
        #expect(controller.text == "(x)")
        #expect(controller.textView.selectedRange().location == 3)
        controller.typeKeys(" `code`")
        #expect(controller.text == "(x) `code`")
    }

    @Test func apostrophesDontPair() {
        let controller = makeEditor("", mode: .raw)
        controller.typeKeys("don't")
        #expect(controller.text == "don't")
    }

    @Test func markersWrapTheSelection() {
        let controller = makeEditor("make it bold", mode: .raw, caret: 12)
        controller.textView.setSelectedRange(NSRange(location: 8, length: 4))
        controller.typeKeys("*")
        controller.typeKeys("*")
        #expect(controller.text == "make it **bold**")
        #expect(controller.textView.selectedRange() == NSRange(location: 10, length: 4))
    }

    @Test func backspaceRemovesAnEmptyPair() {
        let controller = makeEditor("", mode: .raw)
        controller.typeKeys("[")
        #expect(controller.text == "[]")
        controller.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(controller.text == "")
    }

    @Test func pairingCanBeTurnedOff() {
        let controller = makeEditor("", mode: .raw)
        controller.autoPairs = false
        controller.typeKeys("(")
        #expect(controller.text == "(")
    }

    @Test func typedShortcutsSurviveAutoPairing() {
        let fence = makeEditor("", mode: .preview)
        fence.typeKeys("```")
        #expect(fence.text.hasPrefix("```"))
        #expect(!fence.text.hasPrefix("````"))
        let list = makeEditor("", mode: .preview)
        list.typeKeys("[] ")
        #expect(list.text == "- [ ] ")
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
        let controller = makeEditor("Ravens fly quickly over `dark` hills.", mode: .preview, caret: 0)
        var theme = controller.theme
        theme.partsOfSpeech = Set(PartOfSpeech.allCases)
        controller.theme = theme
        let palette = controller.styler.theme.current.palette
        let text = controller.text as NSString
        #expect(controller.color(at: text.range(of: "fly").location) == palette.link)
        #expect(controller.color(at: text.range(of: "quickly").location) == palette.magic)
        #expect(controller.color(at: text.range(of: "dark").location) != palette.caret)
    }
}
#endif
