#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct SpellsMenuTests {
    func editorAtEnd(_ text: String = "") -> EditorController {
        makeEditor(text, caret: (text as NSString).length, freshDefaults: true)
    }

    @Test func slashOpensFiltersAndCasts() {
        let controller = editorAtEnd("Intro\n\n")
        controller.type("/")
        #expect(controller.spellSession != nil)
        #expect(controller.spellsMenu.model.title == "Spells")
        #expect(controller.spellsMenu.model.items.count == Spellbook.standard.count)
        controller.type("h2")
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        controller.press(#selector(NSResponder.insertNewline(_:)))
        #expect(controller.text == "Intro\n\n## ")
        #expect(controller.spellSession == nil)
        #expect(controller.recentSpells == ["h2"])
    }

    @Test func castsInRawMode() {
        let controller = editorAtEnd("Intro\n\n")
        controller.mode = .raw
        controller.type("/h2")
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        controller.press(#selector(NSResponder.insertNewline(_:)))
        #expect(controller.text == "Intro\n\n## ")
        #expect(controller.spellSession == nil)
    }

    @Test func arrowsMoveTheSelection() {
        let controller = editorAtEnd()
        controller.type("/")
        controller.press(#selector(NSResponder.moveDown(_:)))
        controller.press(#selector(NSResponder.moveDown(_:)))
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        controller.press(#selector(NSResponder.moveUp(_:)))
        controller.press(#selector(NSResponder.insertTab(_:)))
        #expect(controller.text == "# ")
    }

    @Test func escapeAndDoubleSlashLeaveALiteralSlash() {
        let controller = editorAtEnd()
        controller.type("/he")
        controller.press(#selector(NSResponder.cancelOperation(_:)))
        #expect(controller.spellSession == nil)
        #expect(controller.text == "/he")

        let other = editorAtEnd()
        other.type("//")
        #expect(other.text == "/")
        #expect(other.spellSession == nil)
    }

    @Test func doesNotTriggerInCodeOrMidWord() {
        let afterWord = editorAtEnd("and")
        afterWord.type("/")
        #expect(afterWord.spellSession == nil)

        let inCode = editorAtEnd("```\n")
        inCode.type("/")
        #expect(inCode.spellSession == nil)

        let inFrontmatter = editorAtEnd("---\ntitle: \n---\n\nBody\n")
        inFrontmatter.textView.setSelectedRange(NSRange(location: 11, length: 0))
        inFrontmatter.type("/")
        #expect(inFrontmatter.spellSession == nil)

        let afterSpace = editorAtEnd("Run ")
        afterSpace.type("/")
        #expect(afterSpace.spellSession != nil)
    }

    @Test func spaceClosesTheMenu() {
        let controller = editorAtEnd()
        controller.type("/h ")
        #expect(controller.spellSession == nil)
        #expect(controller.text == "/h ")
    }

    @Test func codeBlockThenLanguage() {
        let controller = editorAtEnd()
        controller.type("/code")
        controller.press(#selector(NSResponder.insertNewline(_:)))
        #expect(controller.text == "```\n\n```")
        #expect(controller.spellsMenu.model.title == "Language")
        controller.type("sw")
        #expect(controller.spellsMenu.model.selectedItem?.id == "swift")
        controller.press(#selector(NSResponder.insertNewline(_:)))
        #expect(controller.text == "```swift\n\n```")
        #expect(controller.textView.selectedRange().location == 9)
    }
}
#endif
