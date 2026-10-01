import Foundation
import Testing

@testable import GrimoireCore

@Suite struct RoundTripTests {
    @Test func commonMarkSpecExamples() throws {
        for example in try Corpus.examples("commonmark-spec.json") {
            let document = Document(parsing: example.markdown)
            #expect(
                document.markdown == example.markdown,
                "CommonMark example \(example.example ?? 0) (\(example.section ?? ""))")
        }
    }

    @Test func commonMarkSpecAsOneDocument() throws {
        let text = try Corpus.examples("commonmark-spec.json").map(\.markdown).joined(separator: "\n")
        #expect(Document(parsing: text).markdown == text)
        #expect(Document(parsing: text, flavor: .mdx).markdown == text)
    }

    @Test func commonMarkSpecWithWindowsLineEndings() throws {
        for example in try Corpus.examples("commonmark-spec.json") {
            let text = example.markdown.replacingOccurrences(of: "\n", with: "\r\n")
            #expect(Document(parsing: text).markdown == text, "CommonMark example \(example.example ?? 0)")
        }
    }

    @Test func gfmExtensionExamples() throws {
        for (index, example) in try Corpus.examples("gfm-extensions.json").enumerated() {
            #expect(Document(parsing: example.markdown).markdown == example.markdown, "GFM example \(index)")
        }
    }

    @Test(arguments: try Corpus.files(in: "readmes"))
    func readme(_ url: URL) throws {
        let text = try Corpus.text(url)
        #expect(Document(parsing: text).markdown == text)
    }

    @Test(arguments: try Corpus.files(in: "mdx"))
    func mdxPage(_ url: URL) throws {
        let text = try Corpus.text(url)
        #expect(Document(parsing: text, flavor: .mdx).markdown == text)
        #expect(Document(parsing: text, flavor: .markdown).markdown == text)
    }

    @Test(arguments: [
        "", "\n", "\n\n\n", "   ", "no newline at end", "# Title\n\n\n\n", "\n\nleading blank lines\n",
        "---\n", "---\ntitle: unclosed\n", "---\n---\n", "---\na: 1\n---", "\u{FEFF}# BOM\n", "a\rb\r\rc\r",
        "  - indented list\n    - nested\n", "- - nested on one line\n", "> quote\nlazy\n\n",
        "[ref]: /url\n", "para\n[ref]: /url\n\n[other]: /x 'title'\n\nend\n", "```\nunclosed fence\n\n\n",
    ])
    func edgeCase(_ text: String) {
        #expect(Document(parsing: text).markdown == text)
        #expect(Document(parsing: text, flavor: .mdx).markdown == text)
    }
}
