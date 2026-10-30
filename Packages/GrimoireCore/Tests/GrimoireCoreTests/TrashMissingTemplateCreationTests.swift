import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TrashMissingTemplateCreationTests {
    @Test(arguments: ["absent", "restored", "file"])
    func lookupCannotClassifyOrRecreateAnOwnerReservedByAmbiguousTrash(scenario: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source", "posts/keep.md": "keep"])
        defer { workspace.deactivate() }
        let owner = scratch.url.appending(path: "notes/posts").resolvingSymlinksInPath().standardizedFileURL
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        let stale = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        let plan = try workspace.prepareTrash(owner)
        let trash = scratch.url.appending(path: "controlled-trash")
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.trash = { url in
            try FileManager.default.moveItem(at: url, to: trash)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return trash
        }
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if scenario == "restored" { try FileManager.default.moveItem(at: trash, to: owner) }
        if scenario == "file" { try Data("replacement".utf8).write(to: owner) }
        let identity = try? LifecycleIdentity(owner)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        workspace.refreshTemplateAssignments()
        #expect(throws: (any Error).self) { try workspace.prepareDocument(in: owner, filenamePattern: "New") }
        guard case .contextUnavailable = workspace.createDocument(stale, naming: .generated, recovery: .createEmptyOnce)
        else { Issue.record("Even empty-once creation must not bypass an ambiguous trash reservation"); return }
        #expect(workspace.project?.pendingLifecycleOperations.first?.kind == .trash)
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(workspace.unresolvedTemplateAssignments.isEmpty)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
        if let identity { #expect(try LifecycleIdentity(owner) == identity) }
        if scenario == "absent" { #expect(!FileManager.default.fileExists(atPath: owner.path)) }
        if scenario == "file" { #expect(try String(contentsOf: owner, encoding: .utf8) == "replacement") }
        let original = scenario == "restored" ? owner : trash
        #expect(try String(contentsOf: original.appending(path: "keep.md"), encoding: .utf8) == "keep")
        #expect(try String(contentsOf: source, encoding: .utf8) == "source")
    }
}
