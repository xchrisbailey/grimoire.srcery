import Foundation
import GrimoireCore
import Testing

@testable import GrimoireIntelligence

/// Evaluations for #19 on the real on-device model: each command's output has the right
/// shape and round-trips through the block model.
@MainActor @Suite(.enabled(if: modelIsReady), .serialized) struct WritingEvaluations {
    static let notes = """
        ## Release

        We ship the beta on Friday. Chris needs to write the release notes, and someone should \
        update the [download page](https://srcery.computer/grimoire) before then. The `build.sh` \
        script still fails on a clean checkout, so fix that first.

        - Ember draught: strength 3, takes two days
        - Moonwater tincture: strength 12, takes three nights
        - Ink of recall: strength 7, takes one week
        """

    func run(_ command: WritingCommand, _ source: String) async throws -> String {
        var last = ""
        for try await text in IntelligenceService.shared.stream(command, context: WritingContext(source: source)) {
            last = text
        }
        print("EVAL \(command):\n\(last)\n")
        #expect(Document(parsing: last).markdown == last, "doesn't round-trip")
        return last
    }

    @Test func outlinesATopic() async throws {
        let outline = try await run(.outline, "Brewing potions safely at home")
        #expect(outline.hasPrefix("## "))
        #expect(outline.components(separatedBy: "\n- ").count >= 4)
    }

    @Test func turnsAListIntoATable() async throws {
        let list = Self.notes.components(separatedBy: "\n\n").last ?? ""
        let table = try #require(MarkdownTable(parsing: try await run(.table, list)))
        #expect(table.columnCount >= 2)
        #expect(table.rowCount >= 4)
    }

    @Test func findsActionItems() async throws {
        let tasks = try await run(.todo, Self.notes)
        let lines = tasks.split(separator: "\n")
        #expect(lines.count >= 2)
        #expect(lines.allSatisfy { $0.hasPrefix("- [ ] ") })
    }

    @Test func summarizesAsACallout() async throws {
        let summary = try await run(.summarize, Self.notes)
        #expect(summary.hasPrefix("> [!NOTE]\n> "))
    }

    @Test func rewritingKeepsLinksAndCode() async throws {
        let paragraph = Self.notes.components(separatedBy: "\n\n")[1]
        let rewritten = try await run(.rewrite, paragraph)
        #expect(rewritten.contains("(https://srcery.computer/grimoire)"))
        #expect(rewritten.contains("`build.sh`"))
    }

    @Test func translatingKeepsMarkdown() async throws {
        let paragraph = Self.notes.components(separatedBy: "\n\n")[1]
        let french = try await run(.translate(language: "French"), paragraph)
        #expect(french.contains("(https://srcery.computer/grimoire)"))
        #expect(french != paragraph)
    }

    @Test func continuesWriting() async throws {
        let more = try await run(.continueWriting, "# Potions\n\nEvery witch keeps one book of recipes.")
        #expect(more.count > 20)
        #expect(!more.hasPrefix("#"))
    }

    @Test func splitsLongTextIntoParts() {
        let text = (1...40).map { "## Part \($0)\n\nSome words about part \($0)." }.joined(separator: "\n\n")
        let parts = IntelligenceService.parts(of: text, maxCharacters: 200)
        #expect(parts.count >= 20)
        #expect(parts.allSatisfy { $0.count <= 200 })
        #expect(IntelligenceService.callout("One.\n\nTwo.") == "> [!NOTE]\n> One.\n>\n> Two.")
    }
}

@Suite struct ContinuationTests {
    @Test func dropsARepeatedLineAndSpacesTheRest() {
        let source = "# Ink\n\nEvery witch keeps one book"
        #expect(IntelligenceService.continuation("Every witch keeps one book of spells.", of: source) == " of spells.")
        #expect(IntelligenceService.continuation("Every witch keeps", of: source) == "")
        #expect(IntelligenceService.continuation(", and hides it.", of: source) == ", and hides it.")
        #expect(IntelligenceService.continuation("of spells.", of: source) == " of spells.")
        #expect(IntelligenceService.continuation("Then more.", of: source + "\n\n") == "Then more.")
    }
}

@MainActor @Suite struct FrontmatterTests {
    @Test func writesValidYAML() {
        let suggestion = FrontmatterSuggestion(
            title: "Potions \"and\" more", tags: ["Brewing", "home safety"], summary: "How to brew.")
        let yaml = suggestion.yaml
        #expect(
            yaml
                == "---\ntitle: \"Potions \\\"and\\\" more\"\ntags: [brewing, home-safety]\n"
                + "summary: \"How to brew.\"\n---\n\n"
        )
        let document = Document(parsing: yaml + "# Body\n")
        #expect(document.frontmatter?.value(forKey: "summary") == "How to brew.")
    }

    @Test(.enabled(if: modelIsReady)) func suggestsFrontmatterOnTheRealModel() async throws {
        let suggestion = try await IntelligenceService.shared.suggestFrontmatter(for: WritingEvaluations.notes)
        print("EVAL frontmatter:\n\(suggestion.yaml)")
        #expect(!suggestion.title.isEmpty)
        #expect(!suggestion.tags.isEmpty)
    }
}

#if os(macOS)
import AppKit
import GrimoireEditor

/// The "done when" for #19: each spell, cast in the editor, streams in from the real model,
/// undoes in one step, and leaves markdown that round-trips through the block model.
@MainActor @Suite(.enabled(if: modelIsReady), .serialized) struct WritingCommandsInTheEditor {
    func cast(_ spell: String, in text: String, at marker: String, language: String? = nil) async throws {
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false)
        defer { withExtendedLifetime(window) {} }
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(text, flavor: .markdown)
        controller.intelligenceEnabled = true
        var plan: IntelligenceCast?
        controller.onIntelligence = { plan = $0 }
        let trigger = (text as NSString).range(of: marker)
        controller.castIntelligence(named: spell, trigger: trigger.location..<NSMaxRange(trigger), language: language)
        let cast = try #require(plan)
        let commands: [String: WritingCommand] = [
            "continue": .continueWriting, "summarize": .summarize, "outline": .outline, "tabulate": .table,
            "actions": .todo, "translate": .translate(language: language ?? "French"),
        ]
        let raw = IntelligenceService.shared.stream(
            try #require(commands[spell]), context: WritingContext(source: cast.source))
        let wrapped = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await piece in raw { continuation.yield(cast.wrap(piece)) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
        controller.streamInsertion(wrapped, replacing: cast.range, actionName: spell)
        for _ in 0..<1_000 where !controller.isAwaitingKeep { try await Task.sleep(for: .milliseconds(20)) }
        controller.keepStreamedText()
        let result = controller.text
        print("EVAL editor \(spell):\n\(result)\n")
        #expect(result != text)
        #expect(!result.contains(marker))
        #expect(Document(parsing: result).markdown == result)
        controller.textView.undoManager?.undo()
        #expect(controller.text == text)
    }

    static let page =
        "# Release\n\nWe ship on Friday. Chris writes the notes; someone fixes `build.sh` first.\n\n"
        + "- Ember: 3 days\n- Moonwater: 12 nights\n\n/x\n"

    @Test func summarize() async throws { try await cast("summarize", in: Self.page, at: "/x") }
    @Test func actions() async throws { try await cast("actions", in: Self.page, at: "/x") }
    @Test func tabulate() async throws { try await cast("tabulate", in: Self.page, at: "/x") }
    @Test func outline() async throws {
        try await cast("outline", in: "# Plans\n\nBrewing safely at home /x\n", at: "/x")
    }
    @Test func translate() async throws { try await cast("translate", in: Self.page, at: "/x", language: "Spanish") }
    @Test func continueWriting() async throws {
        try await cast("continue", in: "# Ink\n\nEvery witch keeps one book/x", at: "/x")
    }
}
#endif
