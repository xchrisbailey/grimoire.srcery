import Foundation
import GrimoireCore
import Testing

@testable import GrimoireIntelligence

@MainActor @Suite struct TranslationTests {
    @Test func refusesReferenceLinksBeforeDeliveringAnyText() async {
        let source = "Read [download page][release].\n\n[release]: https://srcery.computer/grimoire\n"
        var snapshots: [String] = []
        do {
            for try await text in IntelligenceService.shared.stream(
                .translate(language: "French"), context: WritingContext(source: source))
            {
                snapshots.append(text)
            }
            Issue.record("Unsupported source was accepted")
        } catch {
            #expect(
                error.localizedDescription
                    == "This selection contains Markdown that can't be translated safely. "
                    + "Try a selection with explicit links and plain prose.")
        }
        #expect(snapshots.isEmpty)
    }
}
