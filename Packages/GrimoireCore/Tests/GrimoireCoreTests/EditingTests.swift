import Testing

@testable import GrimoireCore

@Suite struct EditingTests {
    let original = "# Potions\n\nIntro paragraph.\n\n- Mandrake\n- Moonwater\n\nOutro.\n"

    @Test func insertParagraphBetweenBlocks() {
        var document = Document(parsing: original)
        document.insert(.paragraph, text: "New text.", at: 2)
        #expect(
            document.markdown == "# Potions\n\nIntro paragraph.\n\nNew text.\n\n- Mandrake\n- Moonwater\n\nOutro.\n")
    }

    @Test func insertListItemKeepsListTight() {
        var document = Document(parsing: original)
        document.insert(.listItem(.bullet), text: "Phoenix feather", at: 3)
        #expect(
            document.markdown
                == "# Potions\n\nIntro paragraph.\n\n- Mandrake\n- Phoenix feather\n- Moonwater\n\nOutro.\n")
    }

    @Test func insertNestedListItemLinesUpUnderParent() {
        var document = Document(parsing: "1. Boil\n2. Stir\n")
        document.insert(.listItem(ListItem(marker: .bullet, indent: 1)), text: "clockwise", at: 2)
        #expect(document.markdown == "1. Boil\n2. Stir\n   - clockwise\n")
        #expect(
            Document(parsing: document.markdown).blocks.last?.kind == .listItem(ListItem(marker: .bullet, indent: 1)))
    }

    @Test func insertAtEndKeepsFileEnding() {
        var document = Document(parsing: "First")
        document.insert(.paragraph, text: "Second", at: 1)
        #expect(document.markdown == "First\n\nSecond")

        var withNewline = Document(parsing: "First\n")
        withNewline.insert(.heading(level: 2), text: "Second", at: 1)
        #expect(withNewline.markdown == "First\n\n## Second\n")
    }

    @Test func insertIntoEmptyDocument() {
        var document = Document(parsing: "")
        document.insert(.heading(level: 1), text: "Hello", at: 0)
        #expect(document.markdown == "# Hello\n")
    }

    @Test func deleteBlocks() {
        var document = Document(parsing: original)
        document.remove(at: 1)
        #expect(document.markdown == "# Potions\n\n- Mandrake\n- Moonwater\n\nOutro.\n")
        document.remove(at: 3)
        #expect(document.markdown == "# Potions\n\n- Mandrake\n- Moonwater\n")
        document.remove(at: 1)
        #expect(document.markdown == "# Potions\n\n- Moonwater\n")
    }

    @Test func moveBlocks() {
        var document = Document(parsing: original)
        document.move(from: 4, to: 0)
        #expect(document.markdown == "Outro.\n\n# Potions\n\nIntro paragraph.\n\n- Mandrake\n- Moonwater\n")
        document.move(from: 0, to: 4)
        #expect(document.markdown == original)
    }

    @Test func moveListItemWithinList() {
        var document = Document(parsing: "- a\n- b\n- c\n")
        document.move(from: 2, to: 0)
        #expect(document.markdown == "- c\n- a\n- b\n")
    }

    @Test func moveListItemOutOfListGetsBlankLines() {
        var document = Document(parsing: original)
        document.move(from: 2, to: 0)
        #expect(document.markdown == "- Mandrake\n\n# Potions\n\nIntro paragraph.\n\n- Moonwater\n\nOutro.\n")
    }

    @Test func convertBetweenKinds() {
        var document = Document(parsing: original)
        document.convert(at: 1, to: .heading(level: 2))
        #expect(document.blocks[1].source == "## Intro paragraph.")
        document.convert(at: 1, to: .listItem(.task))
        #expect(document.blocks[1].source == "- [ ] Intro paragraph.")
        document.convert(at: 1, to: .blockquote)
        #expect(document.blocks[1].source == "> Intro paragraph.")
        document.convert(at: 1, to: .codeBlock(language: "swift"))
        #expect(document.blocks[1].source == "```swift\nIntro paragraph.\n```")
        document.convert(at: 1, to: .paragraph)
        #expect(document.markdown == original)
    }

    @Test func convertListItemToHeadingAddsBlankLines() {
        var document = Document(parsing: original)
        document.convert(at: 2, to: .heading(level: 3))
        #expect(document.markdown == "# Potions\n\nIntro paragraph.\n\n### Mandrake\n\n- Moonwater\n\nOutro.\n")
    }

    @Test func convertToParagraphEscapesMarkers() {
        var document = Document(parsing: "Plain\n")
        document.setText("# not a heading", at: 0)
        #expect(document.blocks[0].source == "\\# not a heading")
        document.setText("1. not a list", at: 0)
        #expect(document.blocks[0].source == "1\\. not a list")
        document.setText("#hashtag is fine", at: 0)
        #expect(document.blocks[0].source == "#hashtag is fine")
    }

    @Test func convertMultilineListItem() {
        var document = Document(parsing: "- first line\n  second line\n")
        #expect(document.blocks[0].text == "first line\nsecond line")
        document.convert(at: 0, to: .blockquote)
        #expect(document.markdown == "> first line\n> second line\n")
    }

    @Test func codeFenceGrowsAroundBackticks() {
        var document = Document(parsing: "x\n")
        document.convert(at: 0, to: .codeBlock(language: nil))
        document.setText("```\nnested\n```", at: 0)
        #expect(document.blocks[0].source == "````\n```\nnested\n```\n````")
        #expect(document.blocks[0].text == "```\nnested\n```")
    }

    @Test func headingTextStripsMarkers() {
        #expect(Document(parsing: "## Closed ##\n").blocks[0].text == "Closed")
        #expect(Document(parsing: "#\n").blocks[0].text == "")
        #expect(Document(parsing: "Setext\n---\n").blocks[0].text == "Setext")
        #expect(Document(parsing: "# C# tips\n").blocks[0].text == "C# tips")
    }

    @Test func editsUseTheFilesLineEnding() {
        var document = Document(parsing: "a\r\n\r\nb\r\n")
        document.insert(.blockquote, text: "one\ntwo", at: 1)
        #expect(document.markdown == "a\r\n\r\n> one\r\n> two\r\n\r\nb\r\n")
    }

    @Test func replaceSourceReparsesOnlyThatBlock() {
        var document = Document(parsing: original)
        let untouched = document.blocks.map(\.id)
        let range = document.replaceSource(at: 1, with: "Split here.\n\nInto two.")
        #expect(range == 1..<3)
        #expect(document.blocks[1].id == untouched[1])
        #expect(
            document.blocks.map(\.kind) == [
                .heading(level: 1), .paragraph, .paragraph, .listItem(.bullet), .listItem(.bullet), .paragraph,
            ])
        #expect(document.markdown == "# Potions\n\nSplit here.\n\nInto two.\n\n- Mandrake\n- Moonwater\n\nOutro.\n")
    }

    @Test func replaceSourceCanChangeKind() {
        var document = Document(parsing: original)
        document.replaceSource(at: 1, with: "## Now a heading")
        #expect(document.blocks[1].kind == .heading(level: 2))
        document.replaceSource(at: 3, with: "  - now nested")
        #expect(document.blocks[3].kind == .listItem(ListItem(marker: .bullet, indent: 1)))
        #expect(document.markdown == Document(parsing: document.markdown).markdown)
    }
}
