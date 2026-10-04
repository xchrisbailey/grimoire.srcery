#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@MainActor @Suite(.serialized) struct SpellingTests {
    static let sample = """
        ---
        title: Thsi wrng
        lang: en
        ---

        Thsi is wrng, see `wrng code` and [a lnk](https://exmple.com/wrng) or https://wrng.example.

        ```swift
        let wrng = "say"
        ```

        <div class="wrng">wrng</div>

        """

    func substring(_ text: String, _ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    @Test func excludesEverythingButProse() {
        let text = Self.sample as NSString
        let index = BlockIndex(text: Self.sample)
        let excluded = ProseExclusions.ranges(in: NSRange(location: 0, length: text.length), text: text, index: index)
        let pieces = excluded.map { text.substring(with: $0) }
        #expect(pieces.first?.hasPrefix("---\ntitle") == true)
        #expect(pieces.contains("`wrng code`"))
        #expect(pieces.contains("](https://exmple.com/wrng)"))
        #expect(pieces.contains("https://wrng.example"))
        #expect(pieces.contains { $0.hasPrefix("```swift") })
        #expect(pieces.contains { $0.hasPrefix("<div") })
        let prose = text.range(of: "Thsi is wrng")
        #expect(!ProseExclusions.overlaps(prose, excluded))
        #expect(!ProseExclusions.overlaps(text.range(of: "a lnk"), excluded))
    }

    @Test func dropsCheckerResultsOutsideProse() {
        let controller = makeEditor(Self.sample)
        let text = Self.sample as NSString
        let whole = NSRange(location: 0, length: text.length)
        var results: [NSTextCheckingResult] = []
        var search = whole
        while true {
            let found = text.range(of: "wrng", options: [], range: search)
            guard found.location != NSNotFound else { break }
            results.append(.spellCheckingResult(range: found))
            search = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        results.append(.replacementCheckingResult(range: text.range(of: "\"say\""), replacementString: "“say”"))
        let kept = controller.filterCheckingResults(results, in: whole)
        // Only the "wrng" in the prose sentence survives.
        #expect(kept.count == 1)
        #expect(kept.first?.range == NSRange(location: text.range(of: "wrng,").location, length: 4))
    }

    @Test func projectWordsAreNeverMisspelled() {
        let controller = makeEditor(Self.sample)
        let text = Self.sample as NSString
        let word = text.range(of: "Thsi is")
        let result = NSTextCheckingResult.spellCheckingResult(range: NSRange(location: word.location, length: 4))
        #expect(controller.filterCheckingResults([result], in: word).count == 1)
        controller.projectWords = ["thsi"]
        #expect(controller.filterCheckingResults([result], in: word).isEmpty)
    }

    @Test func neverUnderlinesCode() {
        let controller = makeEditor(Self.sample)
        let text = Self.sample as NSString
        let code = text.range(of: "let wrng")
        #expect(controller.textView.isExcludedFromChecking?(code) == true)
        #expect(controller.textView.isExcludedFromChecking?(text.range(of: "Thsi is")) == false)
    }

    @Test func checksInTheFrontmatterLanguage() {
        let controller = makeEditor(Self.sample)
        #expect(controller.documentLanguage == "en")
        let options = controller.checkingOptions([:])
        #expect((options[.orthography] as? NSOrthography)?.dominantLanguage == "en")
        let plain = makeEditor("Just prose.\n")
        #expect(plain.checkingOptions([:]).isEmpty)
    }

    @Test func settingsAndTheEditMenuStayInStep() {
        let controller = makeEditor(Self.sample)
        #expect(controller.textChecking == .spellingOnly)
        var reported: TextChecking?
        controller.onTextCheckingChange = { reported = $0 }
        controller.textChecking = TextChecking()
        #expect(controller.textView.isAutomaticQuoteSubstitutionEnabled)
        controller.textView.toggleAutomaticQuoteSubstitution(nil)
        #expect(reported?.smartQuotes == false)
        #expect(reported?.spelling == true)
    }

    /// The "done when": with smart quotes on, a quote in a code block stays straight. Every
    /// check's results pass through the filter before the text view applies them, and a
    /// substitution inside code is refused even if one got through.
    @Test func quotesInCodeStayStraight() {
        let controller = makeEditor("Prose \"here\n\n```\nlet spell = \"\n```\n")
        controller.textChecking = TextChecking()
        let text = controller.text as NSString
        let proseQuote = text.range(of: "\"")
        let codeQuote = text.range(of: "\"", options: .backwards)
        let results: [NSTextCheckingResult] = [
            .quoteCheckingResult(range: proseQuote, replacementString: "“"),
            .quoteCheckingResult(range: codeQuote, replacementString: "“"),
        ]
        let kept = controller.textView.filterCheckingResults?(results, NSRange(location: 0, length: text.length))
        #expect(kept?.map(\.range) == [proseQuote])

        #expect(controller.textView.shouldChangeText(in: codeQuote, replacementString: "“"))
        controller.textView.handleTextCheckingResults(
            [], forRange: codeQuote, types: NSTextCheckingAllTypes, options: [:],
            orthography: .defaultOrthography(forLanguage: "en"), wordCount: 0)
        #expect(!controller.textView.isApplyingCheckingResults)
    }

    @Test func substitutionsInCodeAreRefused() {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.string = "a \"b\" c"
        textView.isExcludedFromChecking = { $0.location >= 6 }
        textView.isApplyingCheckingResults = true
        #expect(!textView.shouldChangeText(in: NSRange(location: 6, length: 1), replacementString: "”"))
        #expect(textView.shouldChangeText(in: NSRange(location: 2, length: 1), replacementString: "“"))
    }
}
#endif
