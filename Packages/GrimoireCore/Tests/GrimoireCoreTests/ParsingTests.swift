import Foundation
import Testing

@testable import GrimoireCore

@Suite struct ParsingTests {
    @Test func splitsBlocksWithTheirSource() {
        let text = """
            # Title

            A paragraph
            on two lines.

            [ref]: https://example.com

            > A quote

            ```swift
            let x = 1
            ```

            | a | b |
            |---|---|
            | 1 | 2 |

            ---

            ![Alt](cat.png)

            <div>html</div>

            Setext
            ======

            """
        let document = Document(parsing: text)
        #expect(
            document.blocks.map(\.kind) == [
                .heading(level: 1), .paragraph, .linkDefinitions, .blockquote, .codeBlock(language: "swift"),
                .table, .thematicBreak, .image, .html, .heading(level: 1),
            ])
        #expect(
            document.blocks.map(\.source) == [
                "# Title", "A paragraph\non two lines.", "[ref]: https://example.com", "> A quote",
                "```swift\nlet x = 1\n```", "| a | b |\n|---|---|\n| 1 | 2 |", "---", "![Alt](cat.png)",
                "<div>html</div>", "Setext\n======",
            ])
        #expect(document.blocks.dropLast().allSatisfy { $0.trailing == "\n\n" })
        #expect(document.blocks.last?.trailing == "\n")
    }

    @Test func flattensListsIntoItemsWithIndent() {
        let document = Document(
            parsing: "- one\n  - nested\n    - deeper\n- [x] done\n- [ ] todo\n\n3. three\n4. four\n")
        let items = document.blocks.compactMap { block -> ListItem? in
            if case .listItem(let item) = block.kind { return item }
            return nil
        }
        #expect(
            items == [
                ListItem(marker: .bullet, indent: 0),
                ListItem(marker: .bullet, indent: 1),
                ListItem(marker: .bullet, indent: 2),
                ListItem(marker: .bullet, checkbox: .checked),
                ListItem(marker: .bullet, checkbox: .unchecked),
                ListItem(marker: .ordered(3)),
                ListItem(marker: .ordered(4)),
            ])
        #expect(
            document.blocks.map(\.source) == [
                "- one", "  - nested", "    - deeper", "- [x] done", "- [ ] todo", "3. three", "4. four",
            ])
        #expect(document.blocks.map(\.text) == ["one", "nested", "deeper", "done", "todo", "three", "four"])
    }

    @Test func keepsFrontmatterRaw() throws {
        let document = Document(parsing: "---\ntitle: \"Potions\"\nlang: de-DE\nnested:\n  lang: fr\n---\n\n# Hi\n")
        let frontmatter = try #require(document.frontmatter)
        #expect(frontmatter.source == "---\ntitle: \"Potions\"\nlang: de-DE\nnested:\n  lang: fr\n---")
        #expect(frontmatter.trailing == "\n\n")
        #expect(frontmatter.yaml == "title: \"Potions\"\nlang: de-DE\nnested:\n  lang: fr")
        #expect(frontmatter.value(forKey: "lang") == "de-DE")
        #expect(frontmatter.value(forKey: "title") == "Potions")
        #expect(frontmatter.value(forKey: "missing") == nil)
        #expect(document.blocks.map(\.kind) == [.heading(level: 1)])
    }

    @Test func thematicBreakAloneIsNotFrontmatter() {
        let document = Document(parsing: "---\n\nText\n")
        #expect(document.frontmatter == nil)
        #expect(document.blocks.map(\.kind) == [.thematicBreak, .paragraph])
    }

    @Test func mdxSplitsOutImportsExportsAndJSX() throws {
        let url = Corpus.root.appending(path: "mdx/components.mdx")
        let document = Document(parsing: try Corpus.text(url), flavor: .mdx)
        let mdx = document.blocks.filter { $0.kind == .mdx }.map(\.source)
        #expect(mdx.count == 5)
        #expect(mdx[0].hasPrefix("import { Callout }"))
        #expect(mdx[0].hasSuffix("section: 'alchemy',\n}"))
        #expect(mdx[1].hasPrefix("<Callout") && mdx[1].hasSuffix("</Callout>"))
        #expect(mdx[2].hasPrefix("<Tabs>") && mdx[2].hasSuffix("</Tabs>"))
        #expect(mdx[3] == #"<Figure src="/cauldron.png" caption="The cauldron" />"#)
        #expect(mdx[4].hasPrefix("export default function Layout"))

        // Inline JSX stays inside its paragraph, and JSX in a code fence stays code.
        #expect(document.blocks.contains { $0.kind == .paragraph && $0.source.contains("<Badge>base</Badge>") })
        #expect(document.blocks.contains { $0.kind == .codeBlock(language: "jsx") })
    }

    @Test func mdxFragmentsAndUnclosedElements() throws {
        let url = Corpus.root.appending(path: "mdx/fragments.mdx")
        let document = Document(parsing: try Corpus.text(url), flavor: .mdx)
        #expect(document.blocks.map(\.kind) == [.mdx, .paragraph, .mdx, .paragraph])
        #expect(document.blocks[2].source == "<Unclosed prop=\"never closes\">\nstill the same block")
    }

    @Test func markdownFlavorLeavesJSXToTheMarkdownParser() {
        let document = Document(parsing: "import X from 'x'\n\n<Note>\nhi\n</Note>\n", flavor: .markdown)
        #expect(document.blocks.map(\.kind) == [.paragraph, .html])
    }

    @Test func detectsLineEnding() {
        #expect(Document(parsing: "a\r\n\r\nb").lineEnding == "\r\n")
        #expect(Document(parsing: "a\n").lineEnding == "\n")
        #expect(Document(parsing: "a").lineEnding == "\n")
    }

    @Test func flavorFromPathExtension() {
        #expect(DocumentFlavor(pathExtension: "MD") == .markdown)
        #expect(DocumentFlavor(pathExtension: "mdx") == .mdx)
        #expect(DocumentFlavor(pathExtension: "txt") == nil)
    }
}
