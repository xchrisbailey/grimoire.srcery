import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct RootAccessRecoveryTests {
    @Test(arguments: [false, true])
    func relocatedOriginalRootReconcilesPendingIntentWithoutChangingRootGuards(restart: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "saved"])
        let owner = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("notes/target")
        try workspace.assignTemplate(owner.appending(path: "source.md"), to: owner)
        let rootID = try #require(workspace.folders.first?.id)
        let storeDirectory = library.storageURL.deletingLastPathComponent()
        workspace.lifecycleOperations.move = { url, destination in
            let moved = try FileOperations.move(url, into: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: storeDirectory.path)
            return moved
        }
        #expect(workspace.move(owner, into: target).error != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        let relocated = scratch.url.appending(path: "relocated")
        try FileManager.default.moveItem(at: scratch.url.appending(path: "notes"), to: relocated)
        let recovering: Workspace
        if restart {
            workspace.deactivate()
            recovering = Workspace(
                projectID: workspace.projectID,
                library: ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)))
            recovering.activate()
        } else {
            recovering = workspace
        }
        defer {
            workspace.deactivate()
            recovering.deactivate()
        }
        let plan = try recovering.prepareRootAccess(to: rootID, with: relocated)
        #expect(!plan.requiresConfirmation)
        #expect(!recovering.hasPendingLifecycleOperations)
        try recovering.confirmRootAccess(plan)
        let moved = relocated.appending(path: "target/posts")
        let assignment = try #require(try recovering.templateAssignment(for: moved))
        #expect(assignment.state == .active)
        #expect(assignment.owner == FileReference(rootID: rootID, relativePath: "target/posts"))
        #expect(assignment.choice == .useSource(FileReference(rootID: rootID, relativePath: "target/posts/source.md")))
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).project(workspace.projectID)
                == recovering.project)
    }

    @Test func sameBookmarkedRootRelocationPreservesRelativeOwnersAndSources() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "same physical source"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/posts")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: owner)
        let original = workspace.project?.templateAssignments
        let rootID = try #require(workspace.folders.first?.id)
        let moved = scratch.url.appending(path: "relocated")
        try FileManager.default.moveItem(at: root, to: moved)
        workspace.refreshTemplateAssignments()
        #expect(workspace.folders.first?.url?.resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
        #expect(workspace.project?.templateAssignments == original)
        #expect(workspace.unresolvedTemplateAssignments.isEmpty)
        let access = try workspace.prepareRootAccess(to: rootID, with: moved)
        #expect(!access.requiresConfirmation)
        try workspace.regrantAccess(to: rootID, with: moved)
        let restarted = Workspace(
            projectID: workspace.projectID, library: ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)))
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.project?.templateAssignments == original)
        let plan = try restarted.prepareDocument(in: moved.appending(path: "posts"), filenamePattern: "New")
        guard case .published(let document) = restarted.createDocument(plan, naming: .generated) else {
            Issue.record("Same-root relocation must preserve usable references")
            return
        }
        #expect(try String(contentsOf: document.url, encoding: .utf8) == "same physical source")
    }

    @Test func regrantRechecksTargetIdentityAndScopeAfterConfirmation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace()
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        try workspace.disableTemplate(in: root)
        let target = try scratch.folder("target")
        let rootID = try #require(workspace.folders.first?.id)
        let plan = try workspace.prepareRootAccess(to: rootID, with: target)
        let before = library.projects
        try FileManager.default.moveItem(at: target, to: scratch.url.appending(path: "original-target"))
        try scratch.folder("target")
        #expect(throws: (any Error).self) { try workspace.confirmRootAccess(plan) }
        #expect(library.projects == before)
        let fresh = try workspace.prepareRootAccess(to: rootID, with: target)
        try workspace.disableTemplate(in: scratch.folder("notes/other"))
        let changed = library.projects
        #expect(throws: (any Error).self) { try workspace.confirmRootAccess(fresh) }
        #expect(library.projects == changed)
    }

    @Test func differentRootNeedsConfirmedScopeAndFailedCommitKeepsOldAccess() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "old source"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/posts")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: owner)
        let replacement = try scratch.folder("replacement/posts").deletingLastPathComponent()
        try scratch.file("replacement/source.md", "new source")
        let rootID = try #require(workspace.folders.first?.id)
        let before = library.projects
        let plan = try workspace.prepareRootAccess(to: rootID, with: replacement)
        #expect(plan.requiresConfirmation)
        #expect(plan.affectedAssignments == workspace.project?.templateAssignments)
        #expect(library.projects == before)
        #expect(throws: (any Error).self) { try workspace.regrantAccess(to: rootID, with: replacement) }
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) {
            #expect(throws: (any Error).self) { try workspace.confirmRootAccess(plan) }
            #expect(library.projects == before)
            #expect(workspace.folders.first?.url?.resolvingSymlinksInPath() == root.resolvingSymlinksInPath())
        }
        try workspace.confirmRootAccess(plan)
        #expect(workspace.project?.templateAssignments == before.first?.templateAssignments)
        let creation = try workspace.prepareDocument(in: replacement.appending(path: "posts"), filenamePattern: "New")
        guard case .published(let document) = workspace.createDocument(creation, naming: .generated) else {
            Issue.record("Confirmed configuration must use the chosen root, not the former access")
            return
        }
        #expect(try String(contentsOf: document.url, encoding: .utf8) == "new source")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
