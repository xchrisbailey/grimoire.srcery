import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

/// Running AI requests from the window: into the editor, with failures shown plainly.
@MainActor
extension WindowState {
    /// Whether AI features can run for this window's project.
    var intelligenceReady: Bool {
        IntelligenceService.shared.isAvailable(for: project) && document != nil
    }

    /// Streams the response to `request` in place of the selection (or at the caret).
    func castIntoSelection(_ request: IntelligenceRequest, actionName: String) {
        let stream = IntelligenceService.shared.stream(request)
        editor.streamIntoSelection(stream, actionName: actionName) { [weak self] error in
            self?.actions.error = error
        }
    }

    /// Streams the response to `request` in place of `range`.
    func cast(_ request: IntelligenceRequest, replacing range: NSRange, actionName: String) {
        let stream = IntelligenceService.shared.stream(request)
        editor.stream(stream, replacing: range, actionName: actionName) { [weak self] error in
            self?.actions.error = error
        }
    }

    /// Runs an AI spell or selection action the editor planned, streaming the result in.
    func runIntelligence(_ cast: IntelligenceCast) {
        if runImageCommand(cast) { return }
        guard let command = Self.writingCommand(for: cast) else { return }
        let context = WritingContext(source: cast.source, language: cast.codeLanguage)
        let raw = IntelligenceService.shared.stream(command, context: context)
        let wrapped = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await text in raw { continuation.yield(cast.wrap(text)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        let onError: (Error) -> Void = { [weak self] error in self?.actions.error = error }
        editor.stream(wrapped, replacing: cast.range, actionName: Self.actionName(for: cast.command), onError: onError)
    }

    private static let writingCommands: [String: WritingCommand] = [
        "continue": .continueWriting, "summarize": .summarize, "outline": .outline, "tabulate": .table,
        "actions": .todo, "rewrite": .rewrite, "shorten": .shorten, "expand": .expand, "explain": .explainCode,
    ]

    static func writingCommand(for cast: IntelligenceCast) -> WritingCommand? {
        cast.command == "translate" ? .translate(language: cast.language ?? "English") : writingCommands[cast.command]
    }

    static func actionName(for command: String) -> String {
        switch command {
        case "rewrite": String(localized: "Rewrite")
        case "shorten": String(localized: "Shorten")
        case "expand": String(localized: "Expand")
        case "explain": String(localized: "Explain Code")
        default:
            Spellbook.intelligence.first { $0.id == command }.map { String(localized: "Cast \($0.title)") }
                ?? String(localized: "Intelligence")
        }
    }

    #if DEBUG
    /// The #18 debug command: a short paragraph streamed in at the caret.
    func streamTestResponse() {
        castIntoSelection(
            IntelligenceRequest(
                instructions: "You write one short paragraph of plain prose.",
                text: "Write a paragraph about keeping a notebook of spells."),
            actionName: "Test Response")
    }
    #endif
}
