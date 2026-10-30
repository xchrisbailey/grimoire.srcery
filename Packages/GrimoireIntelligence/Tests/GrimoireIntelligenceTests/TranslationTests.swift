import Foundation
import FoundationModels
import GrimoireCore
import Testing

@testable import GrimoireIntelligence

private func renderTranslation(_ translations: [String], source: String) throws -> String {
    let text = try #require(translations.last)
    let result = try GeneratedTranslation.PartiallyGenerated(GeneratedContent(properties: ["text": text]))
    return try result.markdown(source: source, preceding: Array(translations.dropLast()))
}

@MainActor @Suite struct TranslationTests {
    @Test func projectsOneTypedPieceWithoutRequiringTheModelToCompleteAnArray() throws {
        let source = "Read [page](https://x.test) and run `build.sh` now."
        let result = try GeneratedTranslation.PartiallyGenerated(GeneratedContent(properties: ["text": "Lisez"]))
        #expect(try result.markdown(source: source) == "Lisez [page](https://x.test) and run `build.sh` now.")
        let label = try GeneratedTranslation.PartiallyGenerated(GeneratedContent(properties: ["text": "pa"]))
        #expect(
            try label.markdown(source: source, preceding: ["Lisez"])
                == "Lisez [pa](https://x.test) and run `build.sh` now.")
    }

    @Test func preservesRepeatedDestinationsNestedMarkersUnicodeAndLineEndings() throws {
        let source =
            "---\r\ntitle: Original\r\n---\r\n\r\n## Hello 🧪 ##  \r\n\r\n"
            + "- [First **bold** label](<https://x.test/a_(b)> \"Title\") and [second](https://x.test/a_(b))\r\n"
            + "  - *Nested* `build.sh`\r\n\r\n> Keep\r\n>\r\n>     [not prose]\r\n\r\n"
            + "```swift\r\nlet value = \"[id]\"\r\n```\r\n\r\n"
            + "| Left | Right |\r\n| :--- | ---: |\r\n| **bold** | [label](https://x.test) |\r\n\r\n"
            + "\\*literal\\*\r\n"
        let translations = [
            "Bonjour 🧪", "Première", "grasse", "étiquette", "et", "deuxième", "Imbriqué", "Gardez",
            "Gauche", "Droite", "grasse", "étiquette", "littéral",
        ]
        let expected =
            "---\r\ntitle: Original\r\n---\r\n\r\n## Bonjour 🧪 ##  \r\n\r\n"
            + "- [Première **grasse** étiquette](<https://x.test/a_(b)> \"Title\") et "
            + "[deuxième](https://x.test/a_(b))\r\n"
            + "  - *Imbriqué* `build.sh`\r\n\r\n> Gardez\r\n>\r\n>     [not prose]\r\n\r\n"
            + "```swift\r\nlet value = \"[id]\"\r\n```\r\n\r\n"
            + "| Gauche | Droite |\r\n| :--- | ---: |\r\n| **grasse** | [étiquette](https://x.test) |\r\n\r\n"
            + "\\*littéral\\*\r\n"
        #expect(try renderTranslation(translations, source: source) == expected)
    }

    @Test func translatesLinkLabelsWithoutLettingTheModelWriteTheirSyntax() throws {
        let source = "Visit [download page](https://srcery.computer/grimoire) and run `build.sh`."
        #expect(
            try renderTranslation(["Visitez", "page de téléchargement", "et lancez"], source: source)
                == "Visitez [page de téléchargement](https://srcery.computer/grimoire) et lancez `build.sh`.")
    }

    @Test(arguments: [
        "Read [download page][release].\n\n[release]: https://srcery.computer/grimoire\n",
        "Read [download page][release].", "Read [release][]", "Read [release]",
        "Read [ambiguous", "[release]: https://srcery.computer/grimoire", "![image][release]",
        "> Read [release]", "- Read [release]",
    ])
    func refusesReferenceLinksBeforeDeliveringAnyText(source: String) async {
        var snapshots: [String] = []
        do {
            for try await text in IntelligenceService.shared.stream(
                .translate(language: "French"), context: WritingContext(source: source))
            {
                snapshots.append(text)
            }
            Issue.record("Unsupported source was accepted")
        } catch {
            #expect(error as? IntelligenceError == .unsupportedTranslationSource)
            #expect(
                error.localizedDescription
                    == "This selection contains Markdown that can't be translated safely. "
                    + "Try a selection with explicit links and plain prose.")
        }
        #expect(snapshots.isEmpty)
    }

    @Test func rejectsMissingUnusableAndOutOfRangeGeneratedFields() throws {
        let source = "Visit [download page](https://srcery.computer/grimoire) and run `build.sh`."
        let missing = try GeneratedTranslation.PartiallyGenerated(GeneratedContent(json: "{}"))
        #expect(throws: IntelligenceError.invalidTranslation) { try missing.markdown(source: source) }
        for text in [
            "", "page\nmodifiée", "page [https://srcery.computer/grimoire]", "[page](https://other.test)",
            "**page**", "`page`", "https://other.test", "...",
        ] {
            let result = try GeneratedTranslation.PartiallyGenerated(GeneratedContent(properties: ["text": text]))
            #expect(throws: IntelligenceError.invalidTranslation) {
                try result.markdown(source: source, preceding: ["Visitez"])
            }
        }
        let partial = try GeneratedTranslation.PartiallyGenerated(
            GeneratedContent(properties: ["text": "et lanc"]))
        #expect(
            try partial.markdown(source: source, preceding: ["Visitez", "page"])
                == "Visitez [page](https://srcery.computer/grimoire) et lanc `build.sh`.")
        #expect(throws: IntelligenceError.invalidTranslation) {
            try partial.markdown(source: source, preceding: ["Visitez", "page", "et lancez"])
        }
    }

    @Test func protectedOnlySelectionsNeedNoGenerationAndPreCancelledRequestsDeliverNothing() async throws {
        let source = "```swift\r\nlet value = \"[release]\"\r\n```\r\n\r\n`[release][]`\r\n"
        var snapshots: [String] = []
        for try await text in IntelligenceService.shared.stream(
            .translate(language: "French"), context: WritingContext(source: source))
        {
            snapshots.append(text)
        }
        #expect(snapshots == [source])
        let task = Task { @MainActor in
            var snapshots: [String] = []
            for try await text in IntelligenceService.shared.stream(
                .translate(language: "French"), context: WritingContext(source: "Read [page](https://x.test)"))
            {
                snapshots.append(text)
            }
            return snapshots
        }
        task.cancel()
        #expect(try await task.value.isEmpty)
    }
}

#if os(macOS)
import AppKit
import GrimoireEditor

@MainActor @Suite(.serialized) struct TranslationInTheEditorTests {
    func waitForCompletion(_ controller: EditorController) async {
        for _ in 0..<100 where controller.isStreaming && !controller.isAwaitingKeep {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test(arguments: [true, false])
    func cancellationAndInvalidResultsRestoreSourceAfterAPartialPreview(failing: Bool) async throws {
        let source = "Read [page](https://x.test) with `build.sh`."
        let partial = try renderTranslation(["Lisez", "pa", "avec"], source: source)
        let controller = EditorController()
        controller.load(source, flavor: .markdown)
        let (stream, producer) = AsyncThrowingStream<String, Error>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        producer.onTermination = { _ in
            stopped.continuation.yield(); stopped.continuation.finish()
        }
        var failure: Error?
        controller.streamInsertion(
            stream, replacing: NSRange(location: 0, length: source.utf16.count), actionName: "Translate"
        ) { failure = $0 }
        producer.yield(partial)
        for _ in 0..<100 where controller.text != partial { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.text == partial)
        if failing {
            let damaged = try GeneratedTranslation.PartiallyGenerated(
                GeneratedContent(properties: ["text": "[https://x.test]"]))
            do {
                producer.yield(try damaged.markdown(source: source, preceding: ["Lisez"]))
                Issue.record("Damaged model output was accepted")
                producer.finish()
            } catch { producer.finish(throwing: error) }
            await waitForCompletion(controller)
            #expect(failure as? IntelligenceError == .invalidTranslation)
        } else {
            controller.discardStreamedText()
        }
        for await _ in stopped.stream { break }
        #expect(controller.text == source)
        #expect(!controller.isStreaming)
    }

    @Test func projectedSnapshotsKeepDiscardUndoAndRejectWithoutDamagingSource() async throws {
        let source = "Visit [download page](https://srcery.computer/grimoire) and run `build.sh`."
        let controller = EditorController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered,
            defer: false)
        defer { withExtendedLifetime(window) {} }
        controller.scrollView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(controller.scrollView)
        controller.load(source, flavor: .markdown)
        let translated = try renderTranslation(["Visitez", "page de téléchargement", "et lancez"], source: source)
        let range = NSRange(location: 0, length: source.utf16.count)
        for keep in [true, false] {
            controller.streamInsertion(
                AsyncThrowingStream {
                    $0.yield(source); $0.yield(translated); $0.finish()
                },
                replacing: range, actionName: "Translate")
            await waitForCompletion(controller)
            #expect(controller.isAwaitingKeep)
            #expect(controller.text == translated)
            if keep {
                controller.keepStreamedText()
                controller.textView.undoManager?.undo()
            } else {
                controller.discardStreamedText()
            }
            #expect(controller.text == source)
        }
        let unsupported = "Read [release][]"
        controller.load(unsupported, flavor: .markdown)
        var failure: Error?
        controller.streamInsertion(
            IntelligenceService.shared.stream(
                .translate(language: "French"), context: WritingContext(source: unsupported)),
            replacing: NSRange(location: 0, length: unsupported.utf16.count), actionName: "Translate"
        ) { failure = $0 }
        await waitForCompletion(controller)
        #expect(failure as? IntelligenceError == .unsupportedTranslationSource)
        #expect(controller.text == unsupported)
        #expect(!controller.isStreaming)
    }
}
#endif
