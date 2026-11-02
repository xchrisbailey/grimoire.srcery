import Foundation
import Testing

@testable import GrimoireCore

private enum HandoffState: CaseIterable, Sendable {
    case unconfigured, configured, settingsFailure, throwsAfterMove
}

@MainActor @Suite(.mainActorGate) struct LifecycleHandoffTests {
    @Test(arguments: [false, true], HandoffState.allCases)
    private func verifiedOriginalStillFollowsTheActualMove(rename: Bool, state: HandoffState) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/source.md")
        let target = try scratch.folder("notes/target")
        let owner = try scratch.folder("notes/owner")
        if state != .unconfigured { try workspace.assignTemplate(source, to: owner) }
        let document = try OpenDocument(
            url: source, autosaveDelay: .seconds(3600),
            authorizeWrite: { try workspace.authorizeDocumentSave(at: $0) })
        defer { document.discard() }
        document.text = "my unsaved edit"
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.rename = { url, name in
            let moved = try FileOperations.rename(url, to: name)
            try afterMove(state, directory: directory)
            return moved
        }
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try afterMove(state, directory: directory)
            return moved
        }
        let result = rename ? workspace.rename(source, to: "renamed") : workspace.move(source, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.legacyMovedURL == nil)
        #expect((result.error != nil) == (state == .settingsFailure || state == .throwsAfterMove))
        // Both actual callers hand off verified movement before presenting a settings/I/O error.
        document.moved(to: moved)
        #expect(document.save() == (state != .settingsFailure))
        #expect(document.url == moved)
        #expect(
            try String(contentsOf: moved, encoding: .utf8)
                == (state == .settingsFailure ? "original" : "my unsaved edit"))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(workspace.hasPendingLifecycleOperations == (state == .settingsFailure))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(document.save())
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "my unsaved edit")
    }
}

private func afterMove(_ state: HandoffState, directory: URL) throws {
    if state == .settingsFailure {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    }
    if state == .throwsAfterMove { throw CocoaError(.userCancelled) }
}
