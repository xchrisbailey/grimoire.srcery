#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@Suite struct IntelligencePlannerTests {
    func plan(_ text: String, _ command: String, at marker: String = "/x", language: String? = nil) -> IntelligenceCast
    {
        let range = (text as NSString).range(of: marker)
        let planner = IntelligencePlanner(text: text, index: BlockIndex(text: text))
        return planner.plan(command, trigger: range.location..<NSMaxRange(range), language: language)
    }

    func applied(_ text: String, _ cast: IntelligenceCast, _ output: String) -> String {
        (text as NSString).replacingCharacters(in: cast.range, with: cast.wrap(output))
    }

    @Test func continuesFromTheCaret() {
        let text = "# Ink\n\nEvery witch keeps one book/x"
        let cast = plan(text, "continue")
        #expect(cast.source == "# Ink\n\nEvery witch keeps one book")
        #expect(applied(text, cast, " of spells.") == "# Ink\n\nEvery witch keeps one book of spells.")
    }

    @Test func summarizesTheSectionAboveAsItsOwnBlock() {
        let text = "# Notes\n\nIntro.\n\n## Release\n\nShip Friday.\n/x\n\n## Later\n\nMore."
        let cast = plan(text, "summarize")
        #expect(cast.source.hasPrefix("## Release"))
        #expect(!cast.source.contains("Intro"))
        let result = applied(text, cast, "> [!NOTE]\n> Ship it.")
        #expect(result.contains("Ship Friday.\n\n> [!NOTE]\n> Ship it.\n\n## Later"))
    }

    @Test func outlinesTheTopicOnTheLine() {
        let text = "# Plans\n\nBrewing at home /x\n"
        let cast = plan(text, "outline")
        #expect(cast.source == "Brewing at home")
        #expect(applied(text, cast, "## Brewing\n- Ventilate") == "# Plans\n\n## Brewing\n- Ventilate\n")
    }

    @Test func tabulatesTheListAbove() {
        let text = "Intro.\n\n- Ember: 3\n- Moonwater: 12\n\n/x\n"
        let cast = plan(text, "tabulate")
        #expect(cast.source == "- Ember: 3\n- Moonwater: 12")
        #expect(applied(text, cast, "| A | B |") == "Intro.\n\n| A | B |\n")
    }

    @Test func translatesTheLineOrTheBlockAbove() {
        let line = plan("Hello there /x\n", "translate", language: "French")
        #expect(line.source == "Hello there")
        #expect(line.language == "French")
        let above = plan("A paragraph.\n\n/x\n", "translate", language: "German")
        #expect(above.source == "A paragraph.")
    }

    @Test func plansSelectionActions() {
        let text = "Some prose here.\n\n```swift\nlet a = 1\n```\n"
        let planner = IntelligencePlanner(text: text, index: BlockIndex(text: text))
        let rewrite = planner.plan(action: "rewrite", selection: NSRange(location: 0, length: 16))
        #expect(rewrite?.source == "Some prose here.")
        #expect(planner.plan(action: "rewrite", selection: NSRange(location: 3, length: 0)) == nil)
        let code = (text as NSString).range(of: "let a")
        let explain = try? #require(planner.plan(action: "explain", selection: code))
        #expect(explain?.source == "let a = 1")
        #expect(explain?.codeLanguage == "swift")
        #expect(
            explain.map { applied(text, $0, "It sets a.") }
                == "Some prose here.\n\n```swift\nlet a = 1\n```\n\nIt sets a.\n")
    }
}

@MainActor @Suite(.serialized) struct IntelligenceSpellTests {
    func makeController() -> (EditorController, NSWindow) {
        BrandFontTests.registerRepoFonts()
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false)
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load("# Ink\n\nSome words.\n\n", flavor: .markdown)
        return (controller, window)
    }

    @Test func aiSpellsShowOnlyWhenEnabled() {
        let (controller, window) = makeController()
        defer { withExtendedLifetime(window) {} }
        #expect(!controller.availableSpells.contains { $0.id == "summarize" })
        controller.intelligenceEnabled = true
        #expect(controller.availableSpells.contains { $0.id == "summarize" })
        #expect(Spellbook.matching("summ", in: controller.availableSpells).first?.id == "summarize")
    }

    @Test func castingHandsThePlanToTheApp() {
        let (controller, window) = makeController()
        defer { withExtendedLifetime(window) {} }
        controller.intelligenceEnabled = true
        var received: IntelligenceCast?
        controller.onIntelligence = { received = $0 }
        let end = (controller.text as NSString).length
        controller.textView.setSelectedRange(NSRange(location: end, length: 0))
        controller.textView.insertText("/summ", replacementRange: controller.textView.selectedRange())
        controller.openSpells(at: end)
        let position = controller.spellsMenu.model.items.firstIndex { $0.id == "summarize" }
        controller.chooseSpell(position ?? 0)
        #expect(received?.command == "summarize")
        #expect(received?.range.location == end)
    }

    @Test func translateAsksForALanguageFirst() {
        let (controller, window) = makeController()
        defer { withExtendedLifetime(window) {} }
        controller.intelligenceEnabled = true
        var received: IntelligenceCast?
        controller.onIntelligence = { received = $0 }
        let end = (controller.text as NSString).length
        controller.textView.setSelectedRange(NSRange(location: end, length: 0))
        controller.textView.insertText("/translate", replacementRange: controller.textView.selectedRange())
        let spell = Spellbook.intelligence.first { $0.id == "translate" }!
        controller.castIntelligence(spell, trigger: end..<(end + 10))
        #expect(received == nil)
        #expect(controller.spellsMenu.model.items.map(\.id).contains("French"))
        let french = controller.spellsMenu.model.items.firstIndex { $0.id == "French" } ?? 0
        controller.chooseSpell(french)
        #expect(received?.language == "French")
        #expect(received?.source == "Some words.")
    }
}
#endif
