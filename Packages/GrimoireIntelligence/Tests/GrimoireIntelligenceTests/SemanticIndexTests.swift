import Foundation
import Testing

@testable import GrimoireIntelligence

let shippingPage = """
    ---
    title: Shipping
    ---

    # Shipping

    Some thoughts on how we ship.

    ## Release checklist

    Before every release: tag the build, update the changelog, run the smoke tests on a clean \
    Mac, and post the notes in the team channel. We ship on Fridays only before noon.
    """

/// A made-up project: `count` pages on everyday topics, plus a few pages the questions are about.
func syntheticProject(count: Int) -> [IndexSource] {
    let topics = [
        ("Garden", "The tomatoes need water every morning, and the basil is ready to pick."),
        ("Recipes", "Simmer the lentils with cumin and garlic for twenty minutes, then add lemon."),
        ("Travel", "The train to the coast leaves at nine; book the seats by the window."),
        ("Reading", "Finished the novel about the lighthouse keeper; the ending was quiet and sad."),
        ("Fitness", "Ran five kilometres along the river and stretched afterwards."),
        ("Finance", "Paid the electricity bill and moved some savings into the rainy day fund."),
        ("Music", "Practised the scales on the piano and learned the first page of the nocturne."),
        ("Home", "The kitchen tap drips; buy a new washer from the hardware shop."),
    ]
    var sources: [IndexSource] = []
    for number in 0..<count {
        let (topic, sentence) = topics[number % topics.count]
        let text = """
            # \(topic) \(number)

            \(sentence) Day \(number) of keeping notes.

            ## Later

            \(topics[(number + 3) % topics.count].1) Another thought for entry \(number).
            """
        sources.append(
            IndexSource(
                url: URL(filePath: "/project/notes/\(topic.lowercased())-\(number).md"),
                path: "notes/\(topic.lowercased())-\(number).md", modified: Date(timeIntervalSince1970: 1_000),
                text: text))
    }
    sources.append(
        IndexSource(
            url: URL(filePath: "/project/work/shipping.md"), path: "work/shipping.md",
            modified: Date(timeIntervalSince1970: 1_000), text: shippingPage))
    sources.append(
        IndexSource(
            url: URL(filePath: "/project/potions/ember.md"), path: "potions/ember.md",
            modified: Date(timeIntervalSince1970: 1_000),
            text: "# Ember tonic\n\nSteep cinnamon and dried chili in honey for three days. Keep it by the hearth.\n"))
    return sources
}

@Suite struct PassageSplitterTests {
    @Test func splitsAtHeadingsAndSkipsFrontmatter() {
        let text =
            "---\ntitle: X\n---\n\nIntro line.\n\n# One\n\nFirst.\n\n```\n# not a heading\n```\n\n## Two\n\nSecond.\n"
        let passages = PassageSplitter.passages(in: text, url: URL(filePath: "/a.md"), path: "a.md")
        #expect(passages.map(\.heading) == [nil, "One", "Two"])
        #expect(passages[0].text == "Intro line.")
        #expect(passages[1].text.contains("# not a heading"))
        let string = text as NSString
        #expect(string.substring(from: passages[1].location).hasPrefix("# One"))
        #expect(string.substring(from: passages[2].location).hasPrefix("## Two"))
    }

    @Test func cutsLongSectionsAtParagraphs() {
        let paragraph = String(repeating: "word ", count: 100)
        let text = "# Long\n\n" + Array(repeating: paragraph, count: 6).joined(separator: "\n\n")
        let passages = PassageSplitter.passages(in: text, url: URL(filePath: "/a.md"), path: "a.md")
        #expect(passages.count >= 3)
        #expect(passages.allSatisfy { $0.heading == "Long" && $0.text.count < 1_400 })
    }
}

@MainActor @Suite(.enabled(if: SemanticIndex.isAvailable)) struct SemanticIndexTests {
    @Test func findsPagesByMeaning() async {
        let index = SemanticIndex(file: nil)
        index.update(from: syntheticProject(count: 40))
        await index.waitUntilIndexed()
        let hits = await index.search("where did I write about the release checklist?", limit: 3)
        #expect(hits.first?.passage.path == "work/shipping.md")
        #expect(hits.first?.passage.heading == "Release checklist")
        let spicy = await index.search("a warming drink with cinnamon", limit: 3)
        #expect(spicy.first?.passage.path == "potions/ember.md")
    }

    @Test func keepsVectorsBetweenLaunches() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "semantic-\(UUID().uuidString).json")
        let sources = syntheticProject(count: 10)
        let first = SemanticIndex(file: file)
        first.update(from: sources)
        await first.waitUntilIndexed()
        try await Task.sleep(for: .milliseconds(300))
        let second = SemanticIndex(file: file)
        #expect(second.passageCount == first.passageCount)
        second.update(from: sources)
        #expect(!second.isIndexing)
        second.update(from: Array(sources.dropLast()))
        #expect(second.passageCount < first.passageCount)
    }
}

/// The "done when" for #21: about a thousand pages, a question, an answer with citations,
/// in a few seconds on the device.
@MainActor @Suite(.enabled(if: modelIsReady && SemanticIndex.isAvailable), .serialized)
struct ProjectAnswerEvaluations {
    @Test func answersFromAThousandPages() async throws {
        let index = SemanticIndex(file: nil)
        let indexing = ContinuousClock.now
        index.update(from: syntheticProject(count: 1_000))
        await index.waitUntilIndexed()
        print("EVAL indexed \(index.passageCount) passages in \(ContinuousClock.now - indexing)")

        let asking = ContinuousClock.now
        var answer: ProjectAnswer?
        for try await partial in IntelligenceService.shared.answer(
            "Where did I write about the release checklist, and what's on it?", from: index)
        {
            answer = partial
        }
        let elapsed = ContinuousClock.now - asking
        let result = try #require(answer)
        print("EVAL answer in \(elapsed):\n\(result.text)\nSOURCES: \(result.sources.map(\.passage.path))")
        #expect(elapsed < .seconds(10))
        let cited = result.citedNumbers.map { result.sources[$0 - 1].passage.path }
        #expect(cited.contains("work/shipping.md"))
        #expect(result.text.lowercased().contains("changelog") || result.text.lowercased().contains("tag"))
    }

    @Test func saysSoWhenTheNotesDontKnow() async throws {
        let index = SemanticIndex(file: nil)
        index.update(from: syntheticProject(count: 30))
        var answer: ProjectAnswer?
        for try await partial in IntelligenceService.shared.answer("What is the airspeed of a swallow?", from: index) {
            answer = partial
        }
        print("EVAL unknown: \(answer?.text ?? "")")
        #expect(answer?.text.isEmpty == false)
    }
}
