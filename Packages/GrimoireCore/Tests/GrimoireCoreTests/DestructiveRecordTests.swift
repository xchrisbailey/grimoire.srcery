import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DestructiveRecordTests {
    @Test func legacyMoveWithoutKindStillLoadsButUnknownAndNullKindsFailWithoutOverwriting() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        var prepared = Data()
        workspace.lifecycleOperations.rename = { _, _ in
            prepared = try Data(contentsOf: library.storageURL)
            throw CocoaError(.userCancelled)
        }
        _ = workspace.rename(root.appending(path: "source.md"), to: "new")
        let json = try #require(String(data: prepared, encoding: .utf8))
        let legacy = json.replacingOccurrences(
            of: #"(?m)^\s*"kind" : "relocation",\n"#, with: "", options: .regularExpression)
        #expect(legacy != json)
        try Data(legacy.utf8).write(to: library.storageURL)
        let loaded = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(loaded.loadError == nil)
        #expect(loaded.projects.first?.pendingLifecycleOperations.first?.kind == .relocation)
        for replacement in ["\"future\"", "null"] {
            let malformed = json.replacingOccurrences(
                of: "\"kind\" : \"relocation\"", with: "\"kind\" : " + replacement)
            try Data(malformed.utf8).write(to: library.storageURL)
            let rejected = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
            #expect(rejected.loadError != nil)
            #expect(throws: (any Error).self) { try rejected.createProject(named: "Must not overwrite") }
            #expect(try Data(contentsOf: library.storageURL) == Data(malformed.utf8))
        }
    }

    @Test func trashRecordCannotDeleteADependentOwnerOutsideItsRecordedSubtree() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        let plan = try workspace.prepareTrash(root.appending(path: "source.md"))
        var projects: [Project] = []
        workspace.lifecycleOperations.trash = { _ in
            projects = try ProjectStore(fileURL: library.storageURL).load()
            throw CocoaError(.userCancelled)
        }
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
        var project = try #require(projects.first)
        let original = try #require(project.pendingLifecycleOperations.first)
        project.pendingLifecycleOperations = [
            PendingLifecycleOperation(
                kind: .trash, trashRoots: original.trashRoots,
                id: original.id, projectID: original.projectID, source: original.source,
                destination: original.destination,
                rootIdentity: original.rootIdentity, itemIdentity: original.itemIdentity,
                sourceParentIdentity: original.sourceParentIdentity,
                destinationParentIdentity: original.destinationParentIdentity,
                before: original.before, after: [])
        ]
        let malformed = try JSONEncoder().encode(StoredProjects(projects: [project]))
        try malformed.write(to: library.storageURL)
        let rejected = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(rejected.loadError != nil)
        #expect(try Data(contentsOf: library.storageURL) == malformed)
        #expect(try String(contentsOf: root.appending(path: "source.md"), encoding: .utf8) == "saved")
    }
}

private struct StoredProjects: Encodable {
    let version = 1
    let projects: [Project]
}
