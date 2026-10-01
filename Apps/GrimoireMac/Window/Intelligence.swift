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
