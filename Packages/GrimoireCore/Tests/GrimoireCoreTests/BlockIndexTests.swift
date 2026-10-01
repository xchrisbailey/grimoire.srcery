import Foundation
import Testing

@testable import GrimoireCore

@Suite struct BlockIndexTests {
    static let sample = """
        ---
        title: Potions
        ---

        # Potion ledger

        Brews from the autumn batch.

        - [ ] Ember draught
        - [x] Moonwater tincture
          - nested note

        > Keep the volatile ones on the top shelf.

        ```swift
        let brew = "ink"
        ```

        Last paragraph.

        """

    /// Applies `replacement` at `range` to both a full parse and the index, and checks
    /// they agree.
    @discardableResult
    func checkEdit(_ text: String, _ range: Range<Int>, _ replacement: String, flavor: DocumentFlavor = .markdown)
        throws -> (BlockIndex, String)
    {
        var index = BlockIndex(text: text, flavor: flavor)
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: replacement)
        let edited = mutable as String
        index.replace(range, replacementLength: replacement.utf16.count, in: edited)
        let full = Document(parsing: edited, flavor: flavor)
        #expect(index.document.markdown == edited)
        #expect(index.blocks.map(\.kind) == full.blocks.map(\.kind))
        #expect(index.blocks.map(\.source) == full.blocks.map(\.source))
        #expect(index.length == edited.utf16.count)
        for position in index.blocks.indices {
            let source = index.sourceRange(of: position)
            #expect(
                mutable.substring(with: NSRange(location: source.lowerBound, length: source.count))
                    == index.blocks[position].source)
        }
        return (index, edited)
    }

    @Test func offsetsCoverTheText() {
        let index = BlockIndex(text: Self.sample)
        #expect(index.frontmatterRange == 0..<22)
        #expect(index.blocks.first?.kind == .heading(level: 1))
        #expect(index.blockIndex(at: 0) == nil)
        let heading = index.sourceRange(of: 0)
        #expect(
            (Self.sample as NSString).substring(with: NSRange(location: heading.lowerBound, length: heading.count))
                == "# Potion ledger")
        #expect(index.blockIndex(at: index.length) == index.blocks.count - 1)
    }

    @Test func typingInAParagraphReparsesLocally() throws {
        let offset = (Self.sample as NSString).range(of: "autumn").location
        let (index, _) = try checkEdit(Self.sample, offset..<offset, "late ")
        #expect(index.blocks[1].text == "Brews from the late autumn batch.")
    }

    @Test func keepsIdsOfUntouchedBlocks() {
        var index = BlockIndex(text: Self.sample)
        let ids = index.blocks.map(\.id)
        let offset = (Self.sample as NSString).range(of: "Last").location
        let edited = (Self.sample as NSString).replacingCharacters(
            in: NSRange(location: offset, length: 0), with: "The ")
        let changed = index.replace(offset..<offset, replacementLength: 4, in: edited)
        #expect(changed.count <= 3)
        #expect(index.blocks.map(\.id).prefix(5) == ids.prefix(5))
    }

    @Test func openingAFenceFallsBackToAFullParse() throws {
        let offset = (Self.sample as NSString).range(of: "Brews").location
        try checkEdit(Self.sample, offset..<offset, "```\n")
    }

    @Test func editingFrontmatterAndHeadings() throws {
        try checkEdit(Self.sample, 4..<9, "name")
        let offset = (Self.sample as NSString).range(of: "# Potion").location
        try checkEdit(Self.sample, offset..<(offset + 1), "##")
        try checkEdit(Self.sample, offset..<(offset + 2), "")
    }

    @Test func splittingAndJoiningBlocks() throws {
        let offset = (Self.sample as NSString).range(of: " the autumn").location
        try checkEdit(Self.sample, offset..<(offset + 1), "\n\n")
        let blank = (Self.sample as NSString).range(of: "batch.\n\n- [ ]").location + 6
        try checkEdit(Self.sample, blank..<(blank + 2), " ")
    }

    @Test func emptyAndAppendedText() throws {
        try checkEdit("", 0..<0, "# Hi")
        try checkEdit("Para", 4..<4, "\n\n- item")
        try checkEdit("\n\nPara", 0..<0, "Lead\n")
    }

    /// Random edits across the README corpus always match a full parse.
    @Test func randomEditsMatchAFullParse() throws {
        var generator = SeededGenerator(
            seed: UInt64(ProcessInfo.processInfo.environment["GRIMOIRE_SEED"] ?? "42") ?? 42)
        let snippets = ["a", " ", "\n", "\n\n", "# ", "- ", "> ", "```", "*", "1. ", "|", "<div>", "    ", ""]
        let files =
            try Corpus.files(in: "readmes").map { ($0, DocumentFlavor.markdown) }
            + Corpus.files(in: "mdx").map { ($0, DocumentFlavor.mdx) }
        for (url, flavor) in files {
            var text = try Corpus.text(url)
            var index = BlockIndex(text: text, flavor: flavor)
            for _ in 0..<150 {
                let length = text.utf16.count
                let start = Int.random(in: 0...length, using: &generator)
                let end = min(length, start + Int.random(in: 0...6, using: &generator))
                let replacement = snippets.randomElement(using: &generator)!
                let mutable = NSMutableString(string: text)
                mutable.replaceCharacters(in: NSRange(location: start, length: end - start), with: replacement)
                // Skip edits that would split a surrogate pair.
                guard String(mutable).utf16.count == mutable.length else { continue }
                text = mutable as String
                index.replace(start..<end, replacementLength: replacement.utf16.count, in: text)
                let full = Document(parsing: text, flavor: flavor)
                guard index.blocks.map(\.source) == full.blocks.map(\.source),
                    index.blocks.map(\.kind) == full.blocks.map(\.kind)
                else {
                    let diverged = zip(index.blocks, full.blocks).first { $0.source != $1.source || $0.kind != $1.kind }
                    Issue.record(
                        """
                        Index diverged in \(url.lastPathComponent) replacing \(start)..<\(end) \
                        with \(replacement.debugDescription): \(String(describing: diverged))
                        """)
                    return
                }
                #expect(index.document.markdown == text)
            }
        }
    }
}

@Suite struct InlineScannerTests {
    func spans(_ text: String) -> [(InlineSpan.Kind, String)] {
        let nsText = text as NSString
        return InlineScanner.scan(text).map {
            ($0.kind, nsText.substring(with: NSRange(location: $0.content.lowerBound, length: $0.content.count)))
        }
    }

    @Test func emphasisAndStrong() {
        let found = spans("Some **bold**, *italic*, __also bold__ and ~~gone~~.")
        #expect(found.map(\.1) == ["bold", "italic", "also bold", "gone"])
        #expect(found.map(\.0) == [.strong, .emphasis, .strong, .strikethrough])
    }

    @Test func flankingRules() {
        #expect(spans("2 * 3 * 4").isEmpty)
        #expect(spans("snake_case_name").isEmpty)
        #expect(spans("** not bold **").isEmpty)
        #expect(spans("\\*escaped\\*").isEmpty)
    }

    @Test func codeHidesEverythingInside() {
        let found = spans("Run `**not bold**` and ``a ` tick``.")
        #expect(found.map(\.0) == [.code, .code])
        #expect(found.map(\.1) == ["**not bold**", "a ` tick"])
    }

    @Test func linksAndImages() {
        let found = InlineScanner.scan("See [the *docs*](https://x.dev \"t\") and ![cat](img/cat.png).")
        #expect(found.map(\.kind) == [.link(destination: "https://x.dev"), .emphasis, .image(source: "img/cat.png")])
        let link = found[0]
        #expect(link.markers.count == 2)
    }

    @Test func autolinks() {
        let found = spans("Go to <https://srcery.computer> or https://example.com/a_b_c.")
        #expect(found.map(\.0) == [.autolink("https://srcery.computer"), .autolink("https://example.com/a_b_c")])
    }

    @Test func offsetsAreUTF16() {
        let found = InlineScanner.scan("🧪 **brew**")
        #expect(found.first?.content == 5..<9)
    }
}

/// A small deterministic generator so failures reproduce.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state ^ (state >> 33)
    }
}
