import GrimoireCore
import GrimoireIntelligence
import SwiftUI

/// Ask your project: a question about the project's pages, answered on the device from the
/// passages that match it, with each source cited.
@MainActor @Observable
final class ProjectAsk {
    var isActive = false
    var question = ""
    private(set) var asked = ""
    private(set) var answer: ProjectAnswer?
    private(set) var isAnswering = false
    private(set) var error: String?
    /// Bumped to ask the question field to take focus.
    private(set) var focusRequest = 0

    @ObservationIgnored private var task: Task<Void, Never>?

    func begin() {
        isActive = true
        focusRequest += 1
    }

    func end() {
        isActive = false
        task?.cancel()
        isAnswering = false
    }

    func ask(_ index: SemanticIndex) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        task?.cancel()
        asked = question
        answer = nil
        error = nil
        isAnswering = true
        task = Task { [weak self] in
            do {
                for try await partial in IntelligenceService.shared.answer(question, from: index) {
                    guard !Task.isCancelled else { return }
                    self?.answer = partial
                }
            } catch {
                self?.error = error.localizedDescription
            }
            self?.isAnswering = false
        }
    }
}

@MainActor
extension WindowState {
    /// The semantic index for this project, made when intelligence is on for it.
    func currentSemanticIndex() -> SemanticIndex? {
        guard let projectID, intelligenceAllowed, SemanticIndex.isAvailable else {
            semantic = nil
            return nil
        }
        if semantic == nil {
            semantic = SemanticIndex(file: SemanticIndex.file(for: projectID))
            indexMeanings()
        }
        return semantic
    }

    /// Embeds pages the project index has read that are new or changed.
    func indexMeanings() {
        guard let semantic = currentSemanticIndex() else { return }
        semantic.update(
            from: index.readDocuments.map {
                IndexSource(url: $0.document.url, path: $0.document.path, modified: $0.modified, text: $0.text)
            })
    }

    /// Whether AI may run for this project (the model itself may still be missing).
    private var intelligenceAllowed: Bool {
        Preferences.shared.intelligenceEnabled(for: project)
    }

    func askProject() {
        guard let index = currentSemanticIndex() else { return }
        ask.ask(index)
    }

    func showAsk() {
        search.end()
        ask.begin()
        _ = currentSemanticIndex()
    }
}
