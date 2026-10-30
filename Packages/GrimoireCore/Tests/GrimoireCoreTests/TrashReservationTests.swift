import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TrashReservationTests {
    @Test(arguments: [false, true], [false, true])
    func preparedTrashSurvivesRestartAndReservesPhysicalAliases(foreign: Bool, resolved: Bool) async throws {
        let fixture = try await TrashReservationFixture()
        defer { fixture.cleanup() }
        let workspace = fixture.workspace
        let requester = foreign ? fixture.foreign : workspace
        let path = resolved ? fixture.actual : fixture.lexical
        let document = try OpenDocument(url: path, authorizeWrite: { try requester.authorizeDocumentSave(at: $0) })
        defer { document.discard() }
        document.text = "dirty retained text"
        #expect(!document.save())
        #expect(document.isDirty)
        #expect(try String(contentsOf: fixture.actual, encoding: .utf8) == "original")
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(throws: (any Error).self) { try requester.prepareTrash(path) }
        #expect(requester.rename(path, to: "changed").error != nil)
        let id = try #require(workspace.pendingTrashConfigurationRemovals.first)
        #expect(throws: (any Error).self) { try workspace.prepareTrashConfigurationRemoval(id) }
        try fixture.restoreParent()
        workspace.reconcileLifecycleOperations()
        #expect(workspace.hasPendingLifecycleOperations)
        let repair = try workspace.prepareTrashConfigurationRemoval(id)
        #expect(try workspace.confirmDestructiveOperation(repair) == .completed)
        document.moved(to: fixture.lexical)
        #expect(document.save())
        #expect(try String(contentsOf: fixture.lexical, encoding: .utf8) == "dirty retained text")
    }
}

@MainActor private struct TrashReservationFixture {
    let scratch: Scratch
    let workspace: Workspace
    let foreign: Workspace
    let lexical: URL
    let actual: URL

    init() async throws {
        scratch = try Scratch()
        let (original, library) = try await scratch.workspace(files: ["parent/source.md": "original"])
        lexical = scratch.url.appending(path: "notes/parent/source.md")
        actual = scratch.url.appending(path: "notes/relocated/source.md")
        let other = try library.createProject(named: "Foreign")
        try library.bindFolder(scratch.url.appending(path: "notes"), to: other.id)
        let owner = try scratch.folder("notes/owner")
        try original.assignTemplate(lexical, to: owner)
        let plan = try original.prepareTrash(lexical)
        var prepared = Data()
        original.lifecycleOperations.trash = { _ in
            prepared = try Data(contentsOf: library.storageURL)
            throw CocoaError(.userCancelled)
        }
        #expect(throws: (any Error).self) { try original.confirmDestructiveOperation(plan) }
        original.deactivate()
        try prepared.write(to: library.storageURL, options: .atomic)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        workspace = Workspace(projectID: original.projectID, library: restarted)
        foreign = Workspace(projectID: other.id, library: restarted)
        workspace.activate()
        foreign.activate()
        #expect(workspace.hasPendingLifecycleOperations)
        try FileManager.default.moveItem(
            at: lexical.deletingLastPathComponent(), to: actual.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(
            at: lexical.deletingLastPathComponent(), withDestinationURL: actual.deletingLastPathComponent())
    }

    func restoreParent() throws {
        try FileManager.default.removeItem(at: lexical.deletingLastPathComponent())
        try FileManager.default.moveItem(
            at: actual.deletingLastPathComponent(), to: lexical.deletingLastPathComponent())
    }

    func cleanup() {
        workspace.deactivate()
        foreign.deactivate()
    }
}
