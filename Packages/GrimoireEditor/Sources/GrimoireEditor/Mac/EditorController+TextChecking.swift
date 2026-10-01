#if os(macOS)
import AppKit
import GrimoireCore

/// Spelling, grammar and substitutions, kept to prose: code, links, HTML, MDX and
/// frontmatter are never underlined or rewritten.
extension EditorController {
    /// Which checks run. Setting it updates the text view; toggling one from the Edit menu
    /// reports back through `onTextCheckingChange`.
    public var textChecking: TextChecking {
        get {
            TextChecking(
                spelling: textView.isContinuousSpellCheckingEnabled, grammar: textView.isGrammarCheckingEnabled,
                correction: textView.isAutomaticSpellingCorrectionEnabled,
                smartQuotes: textView.isAutomaticQuoteSubstitutionEnabled,
                smartDashes: textView.isAutomaticDashSubstitutionEnabled,
                textReplacement: textView.isAutomaticTextReplacementEnabled)
        }
        set {
            guard newValue != textChecking else { return }
            textView.isContinuousSpellCheckingEnabled = newValue.spelling
            textView.isGrammarCheckingEnabled = newValue.grammar
            textView.isAutomaticSpellingCorrectionEnabled = newValue.correction
            textView.isAutomaticQuoteSubstitutionEnabled = newValue.smartQuotes
            textView.isAutomaticDashSubstitutionEnabled = newValue.smartDashes
            textView.isAutomaticTextReplacementEnabled = newValue.textReplacement
        }
    }

    /// Hooks the text view's checking up to the prose filter, and starts with only the
    /// spelling underline until settings arrive.
    func wireTextChecking() {
        textView.isExcludedFromChecking = { [weak self] range in
            guard let self else { return false }
            return ProseExclusions.overlaps(range, self.excludedRanges(touching: range))
        }
        textView.filterCheckingResults = { [weak self] results, range in
            self?.filterCheckingResults(results, in: range) ?? results
        }
        textView.onTextCheckingToggle = { [weak self] in
            guard let self else { return }
            self.onTextCheckingChange?(self.textChecking)
        }
        textChecking = .spellingOnly
    }

    /// The parts of `range` the checker must leave alone.
    func excludedRanges(touching range: NSRange) -> [NSRange] {
        ProseExclusions.ranges(in: range, text: textView.string as NSString, index: index)
    }

    /// The document's language from its frontmatter `lang:`, for checking in that language
    /// instead of the system's.
    var documentLanguage: String? {
        index.document.frontmatter?.value(forKey: "lang")
    }

    func checkingOptions(_ options: [NSSpellChecker.OptionKey: Any]) -> [NSSpellChecker.OptionKey: Any] {
        guard let language = documentLanguage else { return options }
        var options = options
        options[.orthography] = NSOrthography.defaultOrthography(forLanguage: language)
        return options
    }

    /// Drops results that land in code, links and the like, and words the project knows.
    func filterCheckingResults(_ results: [NSTextCheckingResult], in range: NSRange) -> [NSTextCheckingResult] {
        let excluded = excludedRanges(touching: range)
        let text = textView.string as NSString
        let words = Set(projectWords.map { $0.lowercased() })
        return results.filter { result in
            if ProseExclusions.overlaps(result.range, excluded) { return false }
            if result.resultType == .spelling, NSMaxRange(result.range) <= text.length,
                words.contains(text.substring(with: result.range).lowercased())
            {
                return false
            }
            return true
        }
    }

    /// Tells the spell checker about the project's words and clears underlines on them.
    func projectWordsChanged() {
        let checker = NSSpellChecker.shared
        checker.setIgnoredWords(projectWords, inSpellDocumentWithTag: textView.spellCheckerDocumentTag)
        let text = textView.string as NSString
        for word in projectWords where !word.isEmpty {
            var search = NSRange(location: 0, length: text.length)
            while true {
                let found = text.range(of: word, options: [.caseInsensitive], range: search)
                guard found.location != NSNotFound else { break }
                textView.setSpellingState(0, range: found)
                search = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
            }
        }
    }

    /// "Learn Spelling in This Project" for a misspelled word under the pointer.
    func spellingMenuItems(at offset: Int) -> [NSMenuItem] {
        guard onLearnWord != nil, textView.isContinuousSpellCheckingEnabled,
            let word = misspelledWord(at: offset)
        else { return [] }
        let learn = MenuClosure.item(String(localized: "Learn Spelling in This Project")) { [weak self] in
            self?.onLearnWord?(word)
        }
        return [learn, .separator()]
    }

    /// The misspelled word at `offset`, if there is one and it's in prose.
    func misspelledWord(at offset: Int) -> String? {
        let text = textView.string as NSString
        guard offset < text.length else { return nil }
        let wordRange = textView.selectionRange(
            forProposedRange: NSRange(location: offset, length: 0), granularity: .selectByWord)
        guard wordRange.length > 0, !ProseExclusions.overlaps(wordRange, excludedRanges(touching: wordRange))
        else { return nil }
        let word = text.substring(with: wordRange)
        let miss = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: documentLanguage, wrap: false,
            inSpellDocumentWithTag: textView.spellCheckerDocumentTag, wordCount: nil)
        return miss.location == NSNotFound ? nil : word
    }
}
#endif
