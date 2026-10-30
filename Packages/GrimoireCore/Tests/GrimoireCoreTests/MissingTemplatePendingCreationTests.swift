import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct MissingTemplatePendingCreationTests {
    @Test(arguments: [false, true])
    func freshCreationReconcilesObservedPendingOutcomeBeforeClassifyingTheOldOwner(completed: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        let owner = try scratch.folder("notes/posts").resolvingSymlinksInPath().standardizedFileURL
        let target = try scratch.folder("notes/target")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        let storeDirectory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path) }
        workspace.lifecycleOperations.move = { url, destination in
            let moved = completed ? try FileOperations.move(url, into: destination) : url
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: storeDirectory.path)
            if !completed { throw CocoaError(.userCancelled) }
            return moved
        }
        #expect(workspace.move(owner, into: target).error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
        workspace.deactivate()
        let reloaded = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let reopened = Workspace(projectID: workspace.projectID, library: reloaded)
        reopened.activate()
        defer { reopened.deactivate() }
        #expect(reopened.hasPendingLifecycleOperations)
        #expect(reopened.unresolvedTemplateAssignments.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        let plan = try reopened.prepareDocument(in: owner, filenamePattern: "New")
        #expect(!reopened.hasPendingLifecycleOperations)
        #expect(reopened.unresolvedTemplateAssignments.isEmpty)
        let assignment = try #require(reopened.project?.templateAssignments.first)
        #expect(assignment.state == .active)
        #expect(assignment.owner.relativePath == (completed ? "target/posts" : "posts"))
        #expect(FileManager.default.fileExists(atPath: owner.path) == !completed)
        guard case .published(let created) = reopened.createDocument(plan, naming: .generated) else {
            Issue.record("Creation may proceed only after the recorded original outcome is reconciled")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == (completed ? "" : "saved"))
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == reloaded.projects)
    }
}
