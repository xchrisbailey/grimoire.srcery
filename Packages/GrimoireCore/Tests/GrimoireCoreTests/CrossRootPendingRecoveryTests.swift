import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct CrossRootPendingRecoveryTests {
    @Test(arguments: ["source", "destination", "projection"])
    func unavailablePendingRootsCannotOfferDifferentFolderRegrant(role: String) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let (intent, result) = try fixture.captureMove(completed: true)
        let moved = try #require(result.movedURL)
        fixture.workspace.deactivate()
        let store = ProjectStore(fileURL: fixture.library.storageURL)
        try intent.write(to: store.fileURL, options: .atomic)
        var projects = try store.load()
        let id =
            role == "source"
            ? fixture.innerRootID : role == "destination" ? fixture.destinationRootID : fixture.outerRootID
        let index = try #require(projects[0].roots.firstIndex { $0.id == id })
        projects[0].roots[index].bookmark = Data([0])
        try store.save(projects)
        let bytes = try Data(contentsOf: store.fileURL)
        let library = ProjectLibrary(store: store)
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: library)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.folders.first { $0.id == id }?.url == nil)
        let replacement = try fixture.scratch.folder("replacement")
        #expect(throws: (any Error).self) { try restarted.prepareRootAccess(to: id, with: replacement) }
        #expect(restarted.unresolvedTemplateAssignments.isEmpty)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "original {title}")
    }

    @Test(arguments: [false, true], [false, true])
    func pendingKindsKeepProjectedMissingOrReplacedOwnersActiveWithoutCreationSideEffects(
        trash: Bool, replacement: Bool
    ) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let intent = try pendingSourceIntent(trash: trash, fixture: fixture)
        fixture.workspace.deactivate()
        try FileManager.default.removeItem(at: fixture.outerOwner)
        if replacement { try Data("replacement owner".utf8).write(to: fixture.outerOwner) }
        try intent.write(to: fixture.library.storageURL, options: .atomic)
        let library = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        let before = library.projects
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: library)
        restarted.activate()
        defer { restarted.deactivate() }
        restarted.refreshTemplateAssignments()
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.unresolvedTemplateAssignments.isEmpty)
        #expect(throws: (any Error).self) {
            try restarted.prepareDocument(in: fixture.outerOwner, filenamePattern: "Must not recreate")
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == intent)
        if replacement {
            #expect(try String(contentsOf: fixture.outerOwner, encoding: .utf8) == "replacement owner")
        } else {
            #expect(!FileManager.default.fileExists(atPath: fixture.outerOwner.path))
        }
    }

    @Test func originalRootRelocationReconcilesAllSourceCoordinatesBeforeRegrant() async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let (intent, _) = try fixture.captureMove(completed: true)
        fixture.workspace.deactivate()
        try intent.write(to: fixture.library.storageURL, options: .atomic)
        let originalRoot = fixture.scratch.url.appending(path: "notes")
        let relocated = fixture.scratch.url.appending(path: "relocated")
        try FileManager.default.moveItem(at: originalRoot, to: relocated)
        let library = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: library)
        restarted.activate()
        defer { restarted.deactivate() }
        let plan = try restarted.prepareRootAccess(to: fixture.outerRootID, with: relocated)
        #expect(!restarted.hasPendingLifecycleOperations && !plan.requiresConfirmation)
        try restarted.confirmRootAccess(plan)
        let owner = relocated.appending(path: "owner")
        let expected = FileReference(rootID: fixture.destinationRootID, relativePath: "source.md")
        #expect(try restarted.templateAssignment(for: owner)?.choice == .useSource(expected))
        #expect(
            try restarted.templateAssignment(for: relocated.appending(path: "templates/owner"))?.choice
                == .useSource(expected))
        #expect(restarted.unresolvedTemplateAssignments.isEmpty)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    private func pendingSourceIntent(trash: Bool, fixture: LifecycleSourceCoordinateFixture) throws -> Data {
        var intent = Data()
        if trash {
            let plan = try fixture.workspace.prepareTrash(fixture.source)
            fixture.workspace.lifecycleOperations.trash = { _ in
                intent = try Data(contentsOf: fixture.library.storageURL)
                throw CocoaError(.userCancelled)
            }
            #expect(throws: (any Error).self) { try fixture.workspace.confirmDestructiveOperation(plan) }
        } else {
            (intent, _) = try fixture.captureMove(completed: true)
            try Data("replacement source".utf8).write(to: fixture.source)
        }
        return intent
    }
}
