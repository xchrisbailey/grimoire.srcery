import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleKindReservationTests {
    @Test(arguments: [false, true])
    func crossKindSourceDependencyConflictIsRejectedInEitherStoredOrder(trashFirst: Bool) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        defer { fixture.workspace.deactivate() }
        let store = ProjectStore(fileURL: fixture.library.storageURL)
        var relocationProject: Project?
        fixture.workspace.lifecycleOperations.move = { _, _ in
            relocationProject = try store.load().first
            throw CocoaError(.userCancelled)
        }
        _ = fixture.workspace.move(fixture.outerOwner, into: fixture.target)
        var project = try #require(relocationProject)
        let relocation = try #require(project.pendingLifecycleOperations.first)
        var trash: PendingLifecycleOperation?
        fixture.workspace.lifecycleOperations.trash = { _ in
            trash = try store.load().first?.pendingLifecycleOperations.first
            throw CocoaError(.userCancelled)
        }
        let plan = try fixture.workspace.prepareTrash(fixture.source)
        #expect(throws: (any Error).self) { try fixture.workspace.confirmDestructiveOperation(plan) }
        let original = try #require(trash)
        let remaining = original.before.filter { $0.owner.rootID == fixture.innerRootID }
        try #require(remaining.count == 1)
        let scoped = PendingLifecycleOperation(
            kind: .trash, trashRoots: original.trashRoots, id: original.id, projectID: original.projectID,
            source: original.source, destination: original.destination, rootIdentity: original.rootIdentity,
            itemIdentity: original.itemIdentity, sourceParentIdentity: original.sourceParentIdentity,
            destinationParentIdentity: original.destinationParentIdentity, before: remaining, after: remaining)
        project.pendingLifecycleOperations = trashFirst ? [scoped, relocation] : [relocation, scoped]
        let bytes = try JSONEncoder().encode(KindReservationProjects(projects: [project]))
        try bytes.write(to: store.fileURL, options: .atomic)
        let rejected = ProjectLibrary(store: store)
        #expect(rejected.loadError != nil)
        #expect(throws: (any Error).self) { try rejected.createProject(named: "Must not overwrite") }
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "original {title}")
        #expect(FileManager.default.fileExists(atPath: fixture.outerOwner.path))
    }

    @Test(arguments: [false, true], [false, true])
    func bothKindsReservePhysicalAliasesAcrossProjectsWithoutFreezingIndependentPaths(
        trashPending: Bool, foreign: Bool
    ) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        defer { fixture.workspace.deactivate() }
        let otherID = try fixture.library.createProject(named: "Foreign").id
        try fixture.library.bindFolder(fixture.scratch.url.appending(path: "notes"), to: otherID)
        try fixture.library.bindFolder(fixture.target, to: otherID)
        let other = Workspace(projectID: otherID, library: fixture.library)
        other.activate()
        defer { other.deactivate() }
        let actual = try retainPending(trash: trashPending, fixture: fixture)
        let aliasRoot = fixture.scratch.url.appending(path: "notes/alias")
        try FileManager.default.createSymbolicLink(
            at: aliasRoot, withDestinationURL: actual.deletingLastPathComponent())
        let alias = aliasRoot.appending(path: actual.lastPathComponent)
        let requester = foreign ? other : fixture.workspace
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        #expect(throws: (any Error).self) { try requester.prepareTrash(alias) }
        #expect(requester.rename(alias, to: "changed").movedURL == nil)
        #expect(throws: (any Error).self) { try requester.authorizeDocumentSave(at: alias) }
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        let independent = try fixture.scratch.file("notes/free.md", "independent")
        let independentPlan = try requester.prepareTrash(independent)
        #expect(independentPlan.removedChoices.isEmpty && independentPlan.brokenDependencies.isEmpty)
        let result = requester.move(independent, into: fixture.target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        try requester.authorizeDocumentSave(at: moved)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "independent")
        #expect(try String(contentsOf: actual, encoding: .utf8) == "original {title}")
        #expect(fixture.workspace.hasPendingLifecycleOperations)
    }

    private func retainPending(trash: Bool, fixture: LifecycleSourceCoordinateFixture) throws -> URL {
        var intent = Data()
        let actual: URL
        if trash {
            let plan = try fixture.workspace.prepareTrash(fixture.source)
            fixture.workspace.lifecycleOperations.trash = { _ in
                intent = try Data(contentsOf: fixture.library.storageURL)
                throw CocoaError(.userCancelled)
            }
            #expect(throws: (any Error).self) { try fixture.workspace.confirmDestructiveOperation(plan) }
            actual = fixture.source
        } else {
            let result: LifecycleResult
            (intent, result) = try fixture.captureMove(completed: true)
            actual = try #require(result.movedURL)
            try Data("replacement".utf8).write(to: fixture.source)
        }
        try intent.write(to: fixture.library.storageURL, options: .atomic)
        fixture.library.retryLoad()
        #expect(fixture.library.loadError == nil && fixture.workspace.hasPendingLifecycleOperations)
        return actual
    }
}

private struct KindReservationProjects: Encodable {
    let version = 1
    let projects: [Project]
}
