import Foundation
import Testing

@testable import GrimoireCore

@Suite struct TextSearchTests {
    let text = "Ink of recall. INK dries; ink-wells.\nThe inkling waits."

    func found(_ search: TextSearch) -> [String] {
        search.matches(in: text).map { (text as NSString).substring(with: $0) }
    }

    @Test func plainSearchIgnoresCaseByDefault() {
        #expect(found(TextSearch("ink")) == ["Ink", "INK", "ink", "ink"])
        #expect(found(TextSearch("ink", caseSensitive: true)) == ["ink", "ink"])
        #expect(found(TextSearch("ink", wholeWord: true)) == ["Ink", "INK", "ink"])
        #expect(found(TextSearch("a.b")) == [])
    }

    @Test func regularExpressions() {
        #expect(found(TextSearch("^the \\w+", regex: true)) == ["The inkling"])
        #expect(found(TextSearch("i(n)k", regex: true)).count == 4)
        #expect(TextSearch("(", regex: true).isInvalid)
        #expect(!TextSearch("(", regex: false).isInvalid)
        #expect(TextSearch("", regex: true).matches(in: text).isEmpty)
    }

    @Test func replacementsFillInGroups() {
        let search = TextSearch("(\\w+)-wells", regex: true)
        let match = search.matches(in: text)[0]
        #expect(search.replacement(for: match, in: text, template: "$1 pots") == "ink pots")
        #expect(TextSearch("ink").replacement(for: match, in: text, template: "$1") == "$1")
    }
}

@Suite struct FuzzyMatchTests {
    @Test func matchesSubsequencesAndPrefersWordStarts() {
        #expect(FuzzyMatch.score("pl", in: "potion ledger") != nil)
        #expect(FuzzyMatch.score("xz", in: "potion ledger") == nil)
        let ranked = FuzzyMatch.rank(["notes/potion-ledger.md", "notes/plural.md", "apple.md"], by: "plur") { $0 }
        #expect(ranked == ["notes/plural.md"])
        let words = FuzzyMatch.rank(["simple ledger", "potion ledger"], by: "potled") { $0 }
        #expect(words.first == "potion ledger")
        #expect(FuzzyMatch.rank(["b", "a"], by: "") { $0 } == ["b", "a"])
    }
}

@MainActor @Suite struct ProjectIndexTests {
    @Test func listsAndSearchesEveryDocument() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(
            files: [
                "potions.md": "# Potions\n\nInk of recall.\n", "deep/runes.mdx": "Runes need ink too.\n",
                "other.txt": "ink",
            ])
        defer { workspace.deactivate() }
        let index = ProjectIndex()
        index.update(from: workspace.folders)
        #expect(index.documents.map(\.path) == ["notes/deep/runes.mdx", "notes/potions.md"])
        await index.waitUntilRead()
        let results = await index.search(TextSearch("ink"))
        #expect(results.map(\.document.name) == ["runes", "potions"])
        let match = try #require(results.last?.matches.first)
        #expect(match.line == 3)
        #expect(match.preview == "Ink of recall.")
        #expect(match.previewRange == NSRange(location: 0, length: 3))
    }

    @Test func picksUpChangedFiles() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["potions.md": "nothing here\n"])
        defer { workspace.deactivate() }
        let index = ProjectIndex()
        index.update(from: workspace.folders)
        await index.waitUntilRead()
        #expect(await index.search(TextSearch("moonwater")).isEmpty)
        try await Task.sleep(for: .milliseconds(1100))
        try scratch.file("notes/potions.md", "moonwater\n")
        index.update(from: workspace.folders)
        await index.waitUntilRead()
        #expect(await index.search(TextSearch("moonwater")).count == 1)
    }

    @Test func trimsLongLinesAroundTheMatch() {
        let line = String(repeating: "word ", count: 30) + "ink" + String(repeating: " tail", count: 10)
        let match = ProjectIndex.lineMatches([(line as NSString).range(of: "ink")], in: line)[0]
        #expect(match.preview.hasPrefix("…"))
        #expect((match.preview as NSString).substring(with: match.previewRange) == "ink")
    }

    /// The "done when": a project of about 2,000 files searches quickly.
    @Test func searchesTwoThousandFilesQuickly() async throws {
        let scratch = try Scratch()
        var files: [String: String] = [:]
        for number in 0..<2_000 {
            files["folder\(number % 40)/page\(number).md"] =
                "# Page \(number)\n\n" + String(repeating: "Some prose about potions and runes. ", count: 60) + "\n"
        }
        files["folder3/needle.md"] = "The moonwater tincture.\n"
        let (workspace, _) = try await scratch.workspace(files: files)
        defer { workspace.deactivate() }
        try await until(timeout: .seconds(20)) { workspace.folders.first?.tree?.documents.count == 2_001 }
        let index = ProjectIndex()
        index.update(from: workspace.folders)
        await index.waitUntilRead()
        let clock = ContinuousClock()
        var results: [FileMatches] = []
        let elapsed = await clock.measure { results = await index.search(TextSearch("moonwater")) }
        #expect(results.map(\.document.name) == ["needle"])
        let quickOpen = clock.measure { _ = FuzzyMatch.rank(index.documents, by: "f3pg99") { $0.path } }
        print("Searching 2,001 files took \(elapsed); ranking them for quick open took \(quickOpen)")
        #expect(elapsed < .milliseconds(200))
        #expect(quickOpen < .milliseconds(100))
    }
}
