import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TrashRecoveryTests {
    @Test func successfulFilesystemReturnForReplacementDoesNotAuthorizeOriginalSelectionCleanup() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        let plan = try workspace.prepareTrash(source)
        let preserved = scratch.url.appending(path: "preserved.md")
        let trash = scratch.url.appending(path: "controlled-trash.md")
        workspace.lifecycleOperations.trash = { url in
            try FileManager.default.moveItem(at: url, to: preserved)
            try Data("replacement".utf8).write(to: url)
            try FileManager.default.moveItem(at: url, to: trash)
            return trash
        }
        do {
            _ = try workspace.confirmDestructiveOperation(plan)
            Issue.record("A replacement must not count as the original item's verified trash")
        } catch let error as TrashRecoveryError {
            #expect(error.actualTrashSucceeded)
            #expect(!error.originalItemVerified)
        }
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(workspace.project?.templateAssignments == plan.brokenDependencies)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "original")
        #expect(try String(contentsOf: trash, encoding: .utf8) == "replacement")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func scopedRepairPreservesUnrelatedPendingIntentAndChoices() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["first/keep.md": "one", "second/keep.md": "two"])
        defer { workspace.deactivate() }
        let first = scratch.url.appending(path: "notes/first")
        let second = scratch.url.appending(path: "notes/second")
        try workspace.disableTemplate(in: first)
        try workspace.disableTemplate(in: second)
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.trash = { url in
            let destination = scratch.url.appending(path: "controlled-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return destination
        }
        let firstPlan = try workspace.prepareTrash(first)
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(firstPlan) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let firstID = try #require(workspace.pendingTrashConfigurationRemovals.first)
        let repair = try workspace.prepareTrashConfigurationRemoval(firstID)
        let secondPlan = try workspace.prepareTrash(second)
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(secondPlan) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let otherIntent = try #require(workspace.project?.pendingLifecycleOperations.first { $0.id != firstID })
        #expect(try workspace.confirmDestructiveOperation(repair) == .completed)
        #expect(workspace.project?.pendingLifecycleOperations == [otherIntent])
        #expect(workspace.project?.templateAssignments == secondPlan.removedChoices)
        #expect(
            try String(contentsOf: scratch.url.appending(path: "controlled-first/keep.md"), encoding: .utf8) == "one")
        #expect(
            try String(contentsOf: scratch.url.appending(path: "controlled-second/keep.md"), encoding: .utf8) == "two")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test(arguments: [false, true])
    func restartNeverInfersTrashFromAbsenceOrRestorationAndRepairOnlyChangesSettings(restore: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "preserved\r\n"])
        let posts = scratch.url.appending(path: "notes/posts")
        let outside = try scratch.folder("notes/outside")
        let source = posts.appending(path: "source.md")
        try workspace.disableTemplate(in: posts)
        try workspace.assignTemplate(source, to: outside)
        let plan = try workspace.prepareTrash(posts)
        let trash = scratch.url.appending(path: "controlled-trash")
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.trash = { url in
            try FileManager.default.moveItem(at: url, to: trash)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return trash
        }
        do {
            _ = try workspace.confirmDestructiveOperation(plan)
            Issue.record("Final persistence must fail")
        } catch let error as TrashRecoveryError {
            #expect(error.actualTrashSucceeded)
        }
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(workspace.project?.templateAssignments.count == 2)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if restore { try FileManager.default.moveItem(at: trash, to: posts) }
        workspace.deactivate()
        let restartedLibrary = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let restarted = Workspace(projectID: workspace.projectID, library: restartedLibrary)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations)
        restarted.reconcileLifecycleOperations()
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.project?.templateAssignments.count == 2)
        #expect(throws: (any Error).self) { try restarted.authorizeDocumentSave(at: source) }
        #expect(throws: (any Error).self) { try restarted.disableTemplate(in: outside) }
        let id = try #require(restarted.pendingTrashConfigurationRemovals.first)
        let repair = try restarted.prepareTrashConfigurationRemoval(id)
        #expect(repair.removedChoices == plan.removedChoices)
        #expect(repair.brokenDependencies == plan.brokenDependencies)
        try assertRepairFailurePreservesState(restarted, library: restartedLibrary, repair: repair)
        #expect(try restarted.confirmDestructiveOperation(repair) == .completed)
        #expect(!restarted.hasPendingLifecycleOperations)
        #expect(restarted.project?.templateAssignments == repair.brokenDependencies)
        if !restore { try FileManager.default.moveItem(at: trash, to: posts) }
        #expect(try restarted.templateAssignment(for: posts) == nil)
        #expect(try Data(contentsOf: source) == Data("preserved\r\n".utf8))
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == restartedLibrary.projects)
    }

    private func assertRepairFailurePreservesState(
        _ workspace: Workspace, library: ProjectLibrary, repair: DestructiveLifecyclePlan
    ) throws {
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        #expect(try workspace.confirmDestructiveOperation(repair, confirmed: false) == .cancelled)
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(repair) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
    }

    @Test func failedTrashPreparationAndFilesystemCallPreserveChoicesAndContent() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "untouched"])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        try workspace.disableTemplate(in: posts)
        let plan = try workspace.prepareTrash(posts)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        workspace.lifecycleOperations.trash = { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: posts.appending(path: "keep.md"), encoding: .utf8) == "untouched")
    }
}
