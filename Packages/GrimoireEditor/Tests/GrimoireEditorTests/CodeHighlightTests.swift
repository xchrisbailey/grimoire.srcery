#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

@Suite struct CodeHighlighterTests {
    // swiftlint:disable:next large_tuple
    static let samples: [(String, String, String)] = [
        ("swift", "let brew = \"ink\" // stir", "let"),
        ("js", "const brew = 'ink'; // stir", "const"),
        ("typescript", "const brew: string = 'ink'; // stir", "const"),
        ("tsx", "const brew = <Potion color=\"ink\" />; // stir", "const"),
        ("python", "def brew(x):\n    return 'ink'  # stir", "def"),
        ("go", "package main\nfunc brew() int { return 1 } // stir", "func"),
        ("rust", "fn brew() -> u8 { let x = 1; x } // stir", "fn"),
        ("json", "{\"brew\": [1, true, null]}", "1"),
        ("bash", "if [ -f brew ]; then echo \"ink\"; fi # stir", "if"),
        ("html", "<div class=\"brew\">ink</div><!-- stir -->", "div"),
        ("css", ".brew { color: red; } /* stir */", "color"),
        ("c", "int brew(void) { return 0; } // stir", "return"),
        ("cpp", "class Brew { public: int ink; }; // stir", "class"),
        ("ruby", "def brew(x)\n  'ink' # stir\nend", "def"),
        ("yaml", "brew: 'ink' # stir", "brew"),
        ("toml", "[brew]\nink = \"dark\" # stir", "ink"),
        ("sql", "SELECT ink FROM potions WHERE brew = 'dark'; -- stir", "SELECT"),
        ("markdown", "# Potions\n\n- ink\n", "#"),
    ]

    @Test(arguments: samples)
    func everyGrammarHighlights(language: String, code: String, expected: String) {
        let highlights = CodeHighlighter.shared.highlightSync(code, language: language)
        let text = code as NSString
        #expect(!highlights.isEmpty, "no highlights for \(language)")
        #expect(highlights.contains { text.substring(with: $0.range) == expected }, "\(language) missed \(expected)")
    }

    @Test func picksGrammarsByInfoString() {
        #expect(CodeHighlighter.supports("swift"))
        #expect(CodeHighlighter.supports("JS"))
        #expect(CodeHighlighter.supports("ts title=\"potion.ts\""))
        #expect(CodeHighlighter.supports("{.python}"))
        #expect(!CodeHighlighter.supports("brainfork"))
        #expect(!CodeHighlighter.supports(nil))
        #expect(CodeHighlighter.shared.highlightSync("let x = 1", language: "brainfork").isEmpty)
    }

    @Test func mapsCaptureNamesToThemeTokens() {
        #expect(CodeHighlighter.token(for: ["keyword", "function"]) == .keyword)
        #expect(CodeHighlighter.token(for: ["function", "method", "builtin"]) == .function)
        #expect(CodeHighlighter.token(for: ["function", "builtin"]) == .builtin)
        #expect(CodeHighlighter.token(for: ["string", "escape"]) == .escape)
        #expect(CodeHighlighter.token(for: ["punctuation", "bracket"]) == .punctuation)
        #expect(CodeHighlighter.token(for: ["spell"]) == nil)
    }

    @Test func commentsAndStringsComeOutRight() {
        let code = "let brew = \"ink\" // stir"
        let text = code as NSString
        let highlights = CodeHighlighter.shared.highlightSync(code, language: "swift")
        func token(at needle: String) -> CodeToken? {
            let location = text.range(of: needle).location
            return highlights.last { NSLocationInRange(location, $0.range) }?.token
        }
        #expect(token(at: "let") == .keyword)
        #expect(token(at: "ink") == .string)
        #expect(token(at: "// stir") == .comment)
    }
}

@MainActor @Suite(.serialized) struct CodeBlockStylingTests {
    static let sample = """
        # Potions

        ```swift
        let brew = "ink" // stir
        ```

        ```brainfork
        let brew = "ink"
        ```

        """

    var keyword: Int { (Self.sample as NSString).range(of: "let brew").location }
    var string: Int { (Self.sample as NSString).range(of: "\"ink\" //").location + 1 }

    @Test func codeTakesTheThemesColorsInBothModes() {
        let controller = makeEditor(Self.sample, height: 600, dark: true)
        let palette = BrandPalette.mocha
        #expect(controller.color(at: keyword) == palette.magic)
        #expect(controller.color(at: string) == palette.string)
        controller.mode = .raw
        #expect(controller.color(at: keyword) == palette.magic)
        #expect(controller.color(at: string) == palette.string)
        #expect(controller.text == Self.sample)
    }

    @Test func unknownLanguagesStayPlain() {
        let controller = makeEditor(Self.sample, height: 600, dark: true)
        let unknown = (Self.sample as NSString).range(of: "let brew", options: .backwards).location
        #expect(controller.color(at: unknown) == BrandPalette.mocha.ink)
    }

    @Test func highlightsArriveFromTheBackground() async throws {
        let controller = makeEditor(Self.sample, height: 600, dark: true, synchronousHighlighting: false)
        for _ in 0..<100 where controller.color(at: keyword) != BrandPalette.mocha.magic {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.color(at: keyword) == BrandPalette.mocha.magic)
    }

    @Test func editsKeepColorsWhileHighlightingCatchesUp() {
        let styler = MarkdownStyler()
        styler.highlightsSynchronously = true
        let storage = NSMutableAttributedString(string: Self.sample)
        styler.styleAll(storage, index: BlockIndex(text: Self.sample), revealing: nil)
        // The code gets a word added in the middle; runs before and after it keep their colors.
        let edited = "let brew = \"ink\" + x // stir"
        let interim = styler.interimHighlights(for: CodeKey(language: "swift", code: edited))
        let text = edited as NSString
        #expect(interim.contains { text.substring(with: $0.range) == "let" && $0.token == .keyword })
        #expect(interim.contains { text.substring(with: $0.range) == "// stir" && $0.token == .comment })
    }

    @Test func chromeShowsTheLanguageAndChangesIt() {
        let controller = makeEditor(Self.sample, height: 600, dark: true)
        #expect(!controller.codeChrome.isVisible)
        let code = (Self.sample as NSString).range(of: "let brew").location
        controller.textView.setSelectedRange(NSRange(location: code, length: 0))
        #expect(controller.codeChrome.isVisible)
        #expect(controller.codeChrome.languageTitle.hasPrefix("swift"))

        controller.codeChrome.setLanguage("python")
        #expect(controller.text.contains("```python\nlet brew"))
        #expect(controller.textView.selectedRange().location == code + 1)
        controller.textView.undoManager?.undo()
        #expect(controller.text.contains("```swift\nlet brew"))
        controller.codeChrome.setLanguage(nil)
        #expect(controller.text.contains("```\nlet brew"))

        controller.mode = .raw
        #expect(!controller.codeChrome.isVisible)
    }

    @Test func copyPutsJustTheCodeOnThePasteboard() {
        let controller = makeEditor(Self.sample, height: 600, dark: true)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("grimoire-tests-\(UUID().uuidString)"))
        controller.codeChrome.pasteboard = pasteboard
        controller.textView.setSelectedRange(
            NSRange(location: (Self.sample as NSString).range(of: "let brew").location, length: 0))
        controller.codeChrome.copyCode()
        #expect(pasteboard.string(forType: .string) == "let brew = \"ink\" // stir")
        pasteboard.releaseGlobally()
    }

    /// The "done when": typing in a 500-line code block stays smooth.
    @Test func typingInALongCodeBlockStaysQuick() {
        let lines = (1...500).map { "let potion\($0) = brew(\"ink \\($0)\", strength: \($0)) // stir \($0)" }
        let text = "# Long\n\n```swift\n" + lines.joined(separator: "\n") + "\n```\n"
        let controller = makeEditor(text, height: 600, dark: true, synchronousHighlighting: false)
        let offset = (text as NSString).range(of: "potion250 ").location
        controller.textView.setSelectedRange(NSRange(location: offset, length: 0))
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for character in "Ember" {
            let elapsed = clock.measure {
                controller.textView.insertText(String(character), replacementRange: controller.textView.selectedRange())
            }
            slowest = max(slowest, elapsed)
        }
        print("Slowest keystroke in a 500-line code block: \(slowest)")
        // One frame at 60 Hz, with room for a busy test machine.
        #expect(slowest < budget(.milliseconds(40)), "slowest keystroke took \(slowest)")
    }
}
#endif
