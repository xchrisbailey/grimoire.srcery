import Foundation
import Testing

@testable import GrimoireCore

/// Text with `‸` marking the caret.
private func caretText(_ marked: String) -> (String, Int) {
    let range = (marked as NSString).range(of: "‸")
    return ((marked as NSString).replacingCharacters(in: range, with: ""), range.location)
}

/// Runs `action` on `marked` and returns the result with the caret marked again, or nil
/// when the action declined.
private func run(_ marked: String, _ action: (BlockEditing) -> TextEdit?) -> String? {
    let (text, caret) = caretText(marked)
    let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: caret..<caret)
    guard let edit = action(editing) else { return nil }
    let result = edit.applied(to: text) as NSString
    return result.replacingCharacters(in: NSRange(location: edit.selection.lowerBound, length: 0), with: "‸")
}

@Suite struct EnterTests {
    @Test func continuesLists() {
        #expect(run("- Mandrake‸", { $0.newline() }) == "- Mandrake\n- ‸")
        #expect(run("* one‸\n", { $0.newline() }) == "* one\n* ‸\n")
        #expect(run("1. Boil‸", { $0.newline() }) == "1. Boil\n2. ‸")
        #expect(run("9) Stir‸", { $0.newline() }) == "9) Stir\n10) ‸")
        #expect(run("- [x] Done‸", { $0.newline() }) == "- [x] Done\n- [ ] ‸")
        #expect(run("  - nested‸", { $0.newline() }) == "  - nested\n  - ‸")
    }

    @Test func splitsAnItemAtTheCaret() {
        #expect(run("- Mandrake‸ root", { $0.newline() }) == "- Mandrake\n- ‸ root")
    }

    @Test func emptyItemLeavesTheList() {
        #expect(run("- one\n- ‸", { $0.newline() }) == "- one\n‸")
        #expect(run("- one\n  - ‸", { $0.newline() }) == "- one\n- ‸")
    }

    @Test func softBreakStaysInTheBlock() {
        #expect(run("Line one‸", { $0.newline(soft: true) }) == "Line one\n‸")
        #expect(run("- item‸", { $0.newline(soft: true) }) == "- item\n  ‸")
        #expect(run("> quote‸", { $0.newline(soft: true) }) == "> quote\n> ‸")
    }

    @Test func paragraphsAndHeadingsStartANewBlock() {
        #expect(run("Some text‸", { $0.newline() }) == "Some text\n\n‸")
        #expect(run("# Title‸", { $0.newline() }) == "# Title\n\n‸")
    }

    @Test func quotesContinueAndEmptyQuoteLinesEnd() {
        #expect(run("> Keep it high‸", { $0.newline() }) == "> Keep it high\n> ‸")
        #expect(run("> Keep it high\n> ‸", { $0.newline() }) == "> Keep it high\n‸")
    }

    @Test func codeKeepsIndentation() {
        #expect(run("```\n    let x = 1‸\n```", { $0.newline() }) == "```\n    let x = 1\n    ‸\n```")
    }
}

@Suite struct BackspaceTests {
    @Test func listItemTurnsIntoAParagraphFirst() {
        #expect(run("- ‸Mandrake", { $0.backspace() }) == "‸Mandrake")
        #expect(run("- [ ] ‸Task", { $0.backspace() }) == "‸Task")
        #expect(run("- one\n- ‸two", { $0.backspace() }) == "- one\n\n‸two")
        #expect(run("- Man‸drake", { $0.backspace() }) == nil)
    }

    @Test func headingsAndQuotesDropTheirMarker() {
        #expect(run("## ‸Title", { $0.backspace() }) == "‸Title")
        #expect(run("> ‸Quote", { $0.backspace() }) == "‸Quote")
    }

    @Test func paragraphMergesIntoThePreviousBlock() {
        #expect(run("First.\n\n‸Second.", { $0.backspace() }) == "First.‸Second.")
        #expect(run("# Title\n\n‸Body", { $0.backspace() }) == "# Title‸Body")
        #expect(run("```\ncode\n```\n\n‸Body", { $0.backspace() }) == nil)
        #expect(run("‸Only", { $0.backspace() }) == nil)
    }
}

@Suite struct IndentTests {
    @Test func tabNestsUnderThePreviousItem() {
        #expect(run("- one\n- ‸two", { $0.indent(outdent: false) }) == "- one\n  - ‸two")
        #expect(run("1. one\n2. ‸two", { $0.indent(outdent: false) }) == "1. one\n   2. ‸two")
        #expect(run("- ‸first", { $0.indent(outdent: false) }) == "- ‸first")
    }

    @Test func shiftTabMovesOutALevel() {
        #expect(run("- one\n  - ‸two", { $0.indent(outdent: true) }) == "- one\n- ‸two")
        #expect(run("- ‸top", { $0.indent(outdent: true) }) == "- ‸top")
    }

    @Test func continuationLinesMoveWithTheItem() {
        #expect(run("- one\n- ‸two\n  more", { $0.indent(outdent: false) }) == "- one\n  - ‸two\n    more")
    }

    @Test func outsideListsTabTypesNormally() {
        #expect(run("Para‸", { $0.indent(outdent: false) }) == nil)
    }
}

@Suite struct ShortcutTests {
    @Test func bracketsBecomeATask() {
        #expect(run("[] ‸", { $0.shortcut() }) == "- [ ] ‸")
        #expect(run("Intro\n\n[ ] ‸", { $0.shortcut() }) == "Intro\n\n- [ ] ‸")
    }

    @Test func threeBackticksOpenACodeBlock() {
        #expect(run("Intro\n\n```‸", { $0.shortcut() }) == "Intro\n\n```‸\n```")
        // Closing an existing fence adds nothing.
        #expect(run("```\ncode\n```‸", { $0.shortcut() }) == nil)
    }

    @Test func plainMarkdownNeedsNoShortcut() {
        #expect(run("# ‸", { $0.shortcut() }) == nil)
        #expect(run("- ‸", { $0.shortcut() }) == nil)
    }
}

@Suite struct BlockCommandTests {
    @Test func movesBlocksUpAndDown() {
        #expect(run("# A\n\nB‸ para\n\nC\n", { $0.moveBlock(upward: true) }) == "B‸ para\n\n# A\n\nC\n")
        #expect(run("# A\n\nB‸ para\n\nC\n", { $0.moveBlock(upward: false) }) == "# A\n\nC\n\nB‸ para\n")
        #expect(run("- one\n- tw‸o\n", { $0.moveBlock(upward: true) }) == "- tw‸o\n- one\n")
        #expect(run("‸Top\n\nNext", { $0.moveBlock(upward: true) }) == "‸Top\n\nNext")
    }

    @Test func duplicatesBlocks() {
        #expect(run("Para‸\n", { $0.duplicateBlock() }) == "Para\n\nPara‸\n")
        #expect(run("- it‸em\n", { $0.duplicateBlock() }) == "- item\n- it‸em\n")
    }

    @Test func deletesBlocks() {
        #expect(run("One\n\nTw‸o\n\nThree\n", { $0.deleteBlock() }) == "One\n\n‸Three\n")
    }

    @Test func turnsBlocksIntoOtherKinds() {
        #expect(run("Pot‸ion", { $0.convert(to: .heading(level: 2)) }) == "## Pot‸ion")
        #expect(run("## Pot‸ion", { $0.convert(to: .listItem(.task)) }) == "- [ ] Pot‸ion")
        #expect(run("- [ ] Pot‸ion", { $0.convert(to: .paragraph) }) == "Pot‸ion")
    }

    @Test func selectsTheWholeBlock() {
        let (text, caret) = caretText("Intro\n\n- Man‸drake\n- Moon")
        let editing = BlockEditing(text: text, index: BlockIndex(text: text), selection: caret..<caret)
        let selected = editing.blockSelection().map { (text as NSString).substring(with: NSRange($0)) }
        #expect(selected == "- Mandrake")
    }

    @Test func togglesTasks() {
        #expect(run("- [ ] Ember‸", { $0.toggleTask() }) == "- [x] Ember‸")
        #expect(run("- [x] Ember‸", { $0.toggleTask() }) == "- [ ] Ember‸")
        #expect(run("- Plain‸", { $0.toggleTask() }) == nil)
    }
}

@Suite struct TextEditTests {
    @Test func differenceIsMinimal() {
        let edit = TextEdit.difference(from: "abcXYZdef", to: "abc123def", selection: 0..<0)
        #expect(edit.range == 3..<6)
        #expect(edit.replacement == "123")
        #expect(TextEdit.difference(from: "a🧪b", to: "a🔮b", selection: 0..<0).replacement == "🔮")
    }
}

extension NSRange {
    fileprivate init(_ range: Range<Int>) { self.init(location: range.lowerBound, length: range.count) }
}
