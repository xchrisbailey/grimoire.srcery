import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TrashReservationTests {
    @Test func settingsOnlyRepairDoesNotSynchronizeUnrelatedBindingAccess() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let unrelated = try library.bindFolder(try scratch.folder("unrelated"), to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        let plan = try workspace.prepareTrash(root.appending(path: "source.md"))
        var prepared = Data()
        workspace.lifecycleOperations.trash = { _ in
            prepared = try Data(contentsOf: library.storageURL)
            throw CocoaError(.userCancelled)
        }
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
        try prepared.write(to: library.storageURL, options: .atomic)
        library.retryLoad()
        // Another authoritative edit may await its own checked access-release route.
        // Settings-only repair must not take over that unrelated lifetime transition.
        try library.unbindFolder(unrelated.id, from: workspace.projectID)
        let heldRoots = workspace.folders.map(\.id)
        let id = try #require(workspace.pendingTrashConfigurationRemovals.first)
        let repair = try workspace.prepareTrashConfigurationRemoval(id)
        #expect(workspace.folders.map(\.id) == heldRoots)
        #expect(try workspace.confirmDestructiveOperation(repair) == .completed)
        #expect(workspace.folders.map(\.id) == heldRoots)
        #expect(try String(contentsOf: root.appending(path: "source.md"), encoding: .utf8) == "original")
    }

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
        let before = workspace.project
        let storeBytes = try Data(contentsOf: fixture.library.storageURL)
        let inode = try LifecycleIdentity(fixture.lexical)
        #expect(try workspace.confirmDestructiveOperation(repair, confirmed: false) == .cancelled)
        try withBlockedWrites(to: ProjectStore(fileURL: fixture.library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(repair) }
            #expect(workspace.project == before)
            #expect(try Data(contentsOf: fixture.library.storageURL) == storeBytes)
        }
        #expect(document.isDirty)
        #expect(try LifecycleIdentity(fixture.lexical) == inode)
        #expect(try workspace.confirmDestructiveOperation(repair) == .completed)
        #expect(document.isDirty)
        #expect(try LifecycleIdentity(fixture.lexical) == inode)
        #expect(try String(contentsOf: fixture.lexical, encoding: .utf8) == "original")
        document.moved(to: fixture.lexical)
        #expect(document.save())
        #expect(try String(contentsOf: fixture.lexical, encoding: .utf8) == "dirty retained text")
    }
}

@MainActor private struct TrashReservationFixture {
    let scratch: Scratch
    let workspace: Workspace
    let foreign: Workspace
    let library: ProjectLibrary
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
        self.library = restarted
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
