#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized, EditorFixtureScope()) struct SpellsMenuTests {
    enum FixtureError: Error { case interrupted }

    @Test(arguments: [false, true]) func freshEditorPreferencesAreIsolatedAndCleanedUp(interrupted: Bool) async throws {
        var retained: (EditorController, String)?
        do {
            try await withEditorFixtures { @MainActor in
                let controller = makeEditor("", freshDefaults: true)
                let defaults = try #require(controller.defaults as? EditorTestDefaults)
                retained = (controller, defaults.suiteName)
                controller.type("/h2")
                controller.press(#selector(NSResponder.insertNewline(_:)))
                #expect(controller.recentSpells == ["h2"])
                #expect(makeEditor("", freshDefaults: true).recentSpells.isEmpty)
                #expect(defaults.persistentDomain(forName: defaults.suiteName)?["grimoire.recentSpells"] != nil)
                if interrupted { throw FixtureError.interrupted }
            }
        } catch FixtureError.interrupted {
            #expect(interrupted)
        }
        let (controller, suite) = try #require(retained)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        #expect(controller.recentSpells.isEmpty)
        #expect(UserDefaults.standard.persistentDomain(forName: suite)?.isEmpty != false)
    }

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
