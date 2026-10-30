import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateRecoveryPendingTests {
    @Test(arguments: ["locate", "remove", "regrant"], [false, true])
    func restartRepairsPendingIntentBeforeAnyConflictingRecovery(action: String, completed: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "saved"])
        let owner = scratch.url.appending(path: "notes/posts")
        try workspace.assignTemplate(owner.appending(path: "source.md"), to: owner)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        let inactive = try #require(workspace.unresolvedTemplateAssignments.first)
        try scratch.file("notes/posts/source.md", "replacement source is not automatically assigned")
        let target = try scratch.folder("notes/target")
        let locate = try scratch.folder("notes/located")
        let newRoot = try scratch.folder("new-root")
        let rootID = try #require(workspace.project?.roots.first?.id)
        let context = RecoveryContext(assignment: inactive, locate: locate, newRoot: newRoot, rootID: rootID)
        let storeDirectory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path) }
        workspace.lifecycleOperations.move = { url, destination in
            let moved = completed ? try FileOperations.move(url, into: destination) : url
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: storeDirectory.path)
            if !completed { throw CocoaError(.userCancelled) }
            return moved
        }
        let result = workspace.move(owner, into: target)
        #expect(result.error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
        workspace.deactivate()
        let reloaded = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let restarted = Workspace(projectID: workspace.projectID, library: reloaded)
        restarted.activate()
        defer { restarted.deactivate() }
        let before = reloaded.projects
        let bytes = try Data(contentsOf: library.storageURL)
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.project?.templateAssignments == [inactive])
        #expect(throws: (any Error).self) {
            try recover(action, context: context, in: restarted)
        }
        restarted.refreshTemplateAssignments()
        #expect(reloaded.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        try finishRecovery(action, completed: completed, context: context, in: restarted)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == reloaded.projects)
    }

    private func finishRecovery(_ action: String, completed: Bool, context: RecoveryContext, in restarted: Workspace)
        throws
    {
        if completed && action != "regrant" {
            // Reconciliation changes the owner; the old displayed repair scope must now be reviewed again.
            #expect(throws: (any Error).self) {
                try recover(action, context: context, in: restarted)
            }
            #expect(!restarted.hasPendingLifecycleOperations)
            let updated = try #require(restarted.unresolvedTemplateAssignments.first)
            #expect(updated.owner.relativePath == "target/posts")
            #expect(
                updated.choice
                    == .useSource(FileReference(rootID: context.rootID, relativePath: "target/posts/source.md")))
            var updatedContext = context
            updatedContext.assignment = updated
            try recover(action, context: updatedContext, in: restarted)
        } else {
            try recover(action, context: context, in: restarted)
        }
        #expect(!restarted.hasPendingLifecycleOperations)
        if action == "remove" { #expect(restarted.project?.templateAssignments.isEmpty == true) }
        if action == "locate" {
            #expect(try restarted.templateAssignment(for: context.locate)?.state == .active)
        }
        if action == "regrant" {
            #expect(restarted.unresolvedTemplateAssignments.count == 1)
            #expect(restarted.project?.roots.first?.lastKnownURL == context.newRoot)
        }
    }

    @Test func ambiguousPendingSourceMovePreventsFalseMissingOwnerClassification() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder("notes/target")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        var interrupted = Data()
        workspace.lifecycleOperations.move = { url, destination in
            interrupted = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: destination)
        }
        #expect(workspace.move(source, into: target).movedURL != nil)
        workspace.deactivate()
        try interrupted.write(to: library.storageURL, options: .atomic)
        try scratch.file("notes/source.md", "unrelated replacement")
        try FileManager.default.removeItem(at: owner)
        let reloaded = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let restarted = Workspace(projectID: workspace.projectID, library: reloaded)
        restarted.activate()
        defer { restarted.deactivate() }
        restarted.refreshTemplateAssignments()
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.unresolvedTemplateAssignments.isEmpty)
        #expect(restarted.project?.templateAssignments.first?.state == .active)
        #expect(try Data(contentsOf: library.storageURL) == interrupted)
    }

    private struct RecoveryContext {
        var assignment: FolderTemplateAssignment
        let locate: URL
        let newRoot: URL
        let rootID: UUID
    }

    private func recover(_ action: String, context: RecoveryContext, in workspace: Workspace) throws {
        if action == "regrant" {
            let plan = try workspace.prepareRootAccess(to: context.rootID, with: context.newRoot)
            try workspace.confirmRootAccess(plan)
        } else {
            let plan = try workspace.prepareTemplateRecovery(
                context.assignment, locating: action == "locate" ? context.locate : nil)
            try workspace.confirmTemplateRecovery(plan)
        }
    }
}
