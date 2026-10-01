import Foundation
import GrimoireCore
import Testing

@testable import GrimoireEditor

/// Casts `id` where `‸` marks the end of the typed `/query` (the query is everything from
/// the last `/` before the caret).
private func cast(_ id: String, _ marked: String) -> (String, SpellCaster.FollowUp) {
    let caretRange = (marked as NSString).range(of: "‸")
    let text = (marked as NSString).replacingCharacters(in: caretRange, with: "")
    let slash = (text as NSString).range(
        of: "/", options: .backwards, range: NSRange(location: 0, length: caretRange.location))
    var caster = SpellCaster(text: text, trigger: slash.location..<caretRange.location)
    caster.today = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21
    let spell = Spellbook.standard.first { $0.id == id }!
    let result = caster.cast(spell)
    let output = result.edit.applied(to: text) as NSString
    return (
        output.replacingCharacters(in: NSRange(location: result.edit.selection.lowerBound, length: 0), with: "‸"),
        result.followUp
    )
}

@Suite struct SpellCastingTests {
    @Test func turnsTheLineIntoBlocks() {
        #expect(cast("h1", "/h1‸").0 == "# ‸")
        #expect(cast("h2", "Intro\n\n/h2‸").0 == "Intro\n\n## ‸")
        #expect(cast("h3", "/head‸Title").0 == "### ‸Title")
        #expect(cast("bullet", "/list‸").0 == "- ‸")
        #expect(cast("numbered", "/ol‸").0 == "1. ‸")
        #expect(cast("todo", "/todo‸").0 == "- [ ] ‸")
        #expect(cast("quote", "/quote‸").0 == "> ‸")
        #expect(cast("text", "## Title /text‸").0 == "Title ‸")
        #expect(cast("h2", "- item /h2‸").0 == "## item ‸")
    }

    @Test func codeBlockLeavesRoomForTheLanguage() {
        let (text, followUp) = cast("code", "Intro\n\n/code‸")
        #expect(text == "Intro\n\n```‸\n\n```")
        #expect(followUp == .pickLanguage(fenceEnd: 10, codeLine: 11))
        #expect(cast("code", "Intro\n/code‸").0 == "Intro\n\n```‸\n\n```")
    }

    @Test func tablesDividersAndCallouts() {
        #expect(cast("table", "/table‸").0 == "| Column 1 | Column 2 |\n| --- | --- |\n| ‸ |  |\n|  |  |")
        #expect(cast("divider", "Above\n\n/hr‸").0 == "Above\n\n---\n\n‸")
        #expect(cast("callout", "/note‸").0 == "> [!NOTE]\n> ‸")
    }

    @Test func inlineSpells() {
        #expect(cast("link", "See /link‸ here").0 == "See [‸]() here")
        #expect(cast("date", "Due /today‸").0 == "Due 2026-09-21‸")
        #expect(cast("image", "/img‸").1 == .pickImage(offset: 0))
    }

    @Test func frontmatterGoesAtTheTop() {
        #expect(cast("frontmatter", "# Title\n\n/yaml‸").0 == "---\ntitle: ‸\n---\n\n# Title\n\n")
        #expect(cast("frontmatter", "---\ntitle: x\n---\n\nBody /fm‸").0 == "---\n‸title: x\n---\n\nBody ")
    }

    @Test func everySpellCasts() {
        for spell in Spellbook.standard {
            let caster = SpellCaster(text: "/x", trigger: 0..<2)
            #expect(caster.cast(spell).edit.selection.lowerBound >= 0, "\(spell.id)")
        }
    }
}

@Suite struct SpellFilterTests {
    func ids(_ query: String, recent: [String] = []) -> [String] {
        Spellbook.matching(query, recent: recent).map(\.id)
    }

    @Test func filtersByNameAliasAndLetters() {
        #expect(ids("h2").first == "h2")
        #expect(ids("todo").first == "todo")
        #expect(ids("code").first == "code")
        #expect(ids("hd3").contains("h3"))
        #expect(ids("zzz").isEmpty)
        #expect(ids("").count == Spellbook.standard.count)
    }

    @Test func recentSpellsComeFirst() {
        #expect(ids("", recent: ["table", "date"]).prefix(2) == ["table", "date"])
        #expect(ids("h", recent: ["h3"]).first == "h3")
    }
}
