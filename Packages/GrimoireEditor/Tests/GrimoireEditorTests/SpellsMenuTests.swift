#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct SpellsMenuTests {
    func makeController(_ text: String = "") -> EditorController {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        controller.defaults = UserDefaults(suiteName: "grimoire-tests-\(UUID())") ?? .standard
        controller.textView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        controller.load(text, flavor: .markdown)
        controller.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return controller
    }

    func type(_ string: String, into controller: EditorController) {
        for character in string {
            controller.textView.insertText(String(character), replacementRange: controller.textView.selectedRange())
        }
    }

    func press(_ selector: Selector, in controller: EditorController) {
        controller.textView.doCommand(by: selector)
    }

    @Test func slashOpensFiltersAndCasts() {
        let controller = makeController("Intro\n\n")
        type("/", into: controller)
        #expect(controller.spellSession != nil)
        #expect(controller.spellsMenu.model.title == "Spells")
        #expect(controller.spellsMenu.model.items.count == Spellbook.standard.count)
        type("h2", into: controller)
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        #expect(controller.text == "Intro\n\n## ")
        #expect(controller.spellSession == nil)
        #expect(controller.recentSpells == ["h2"])
    }

    @Test func castsInRawMode() {
        let controller = makeController("Intro\n\n")
        controller.mode = .raw
        type("/h2", into: controller)
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        #expect(controller.text == "Intro\n\n## ")
        #expect(controller.spellSession == nil)
    }

    @Test func arrowsMoveTheSelection() {
        let controller = makeController()
        type("/", into: controller)
        press(#selector(NSResponder.moveDown(_:)), in: controller)
        press(#selector(NSResponder.moveDown(_:)), in: controller)
        #expect(controller.spellsMenu.model.selectedItem?.id == "h2")
        press(#selector(NSResponder.moveUp(_:)), in: controller)
        press(#selector(NSResponder.insertTab(_:)), in: controller)
        #expect(controller.text == "# ")
    }

    @Test func escapeAndDoubleSlashLeaveALiteralSlash() {
        let controller = makeController()
        type("/he", into: controller)
        press(#selector(NSResponder.cancelOperation(_:)), in: controller)
        #expect(controller.spellSession == nil)
        #expect(controller.text == "/he")

        let other = makeController()
        type("//", into: other)
        #expect(other.text == "/")
        #expect(other.spellSession == nil)
    }

    @Test func doesNotTriggerInCodeOrMidWord() {
        let afterWord = makeController("and")
        type("/", into: afterWord)
        #expect(afterWord.spellSession == nil)

        let inCode = makeController("```\n")
        type("/", into: inCode)
        #expect(inCode.spellSession == nil)

        let inFrontmatter = makeController("---\ntitle: \n---\n\nBody\n")
        inFrontmatter.textView.setSelectedRange(NSRange(location: 11, length: 0))
        type("/", into: inFrontmatter)
        #expect(inFrontmatter.spellSession == nil)

        let afterSpace = makeController("Run ")
        type("/", into: afterSpace)
        #expect(afterSpace.spellSession != nil)
    }

    @Test func spaceClosesTheMenu() {
        let controller = makeController()
        type("/h ", into: controller)
        #expect(controller.spellSession == nil)
        #expect(controller.text == "/h ")
    }

    @Test func codeBlockThenLanguage() {
        let controller = makeController()
        type("/code", into: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        #expect(controller.text == "```\n\n```")
        #expect(controller.spellsMenu.model.title == "Language")
        type("sw", into: controller)
        #expect(controller.spellsMenu.model.selectedItem?.id == "swift")
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        #expect(controller.text == "```swift\n\n```")
        #expect(controller.textView.selectedRange().location == 9)
    }
}
#endif
