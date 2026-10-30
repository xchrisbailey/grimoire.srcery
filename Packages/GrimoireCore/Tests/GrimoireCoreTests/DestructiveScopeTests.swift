import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DestructiveScopeTests {
    @Test func removingInnerBindingExposesRetainedOuterChoicesWithoutResurrectingInnerOnRebind() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "outer"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let inner = try scratch.folder("notes/inner")
        let child = try scratch.folder("notes/inner/child")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        try workspace.disableTemplate(in: child)
        let outer = workspace.project?.templateAssignments
        let innerRoot = try library.bindFolder(inner, to: workspace.projectID)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: inner)
        let plan = try workspace.prepareUnbind(innerRoot.id)
        #expect(plan.removedChoices.count == 1)
        #expect(try workspace.confirmDestructiveOperation(plan) == .completed)
        #expect(workspace.project?.templateAssignments == outer)
        #expect(try workspace.effectiveTemplateAssignment(for: child)?.choice == .noTemplate)
        let fresh = try library.bindFolder(inner, to: workspace.projectID)
        #expect(fresh.id != innerRoot.id)
        #expect(try workspace.effectiveTemplateAssignment(for: child) == nil)
        #expect(workspace.project?.templateAssignments == outer)
    }

    @Test(arguments: [false, true])
    func confirmationRevalidatesChoicesAndDependenciesWithoutBeingInvalidatedByThemeEdits(trash: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "source"])
        defer { workspace.deactivate() }
        let rootID = try #require(workspace.project?.roots.first?.id)
        let posts = scratch.url.appending(path: "notes/posts")
        let other = try scratch.folder("other")
        try library.bindFolder(other, to: workspace.projectID)
        try workspace.disableTemplate(in: posts)
        let initial = try trash ? workspace.prepareTrash(posts) : workspace.prepareUnbind(rootID)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: other)
        let result = try workspace.confirmDestructiveOperation(initial)
        guard case .reviewNeeded(let updated) = result else {
            Issue.record("A new dependency must require review before destructive commitment")
            return
        }
        #expect(updated.brokenDependencies.count == 1)
        #expect(FileManager.default.fileExists(atPath: posts.path))
        #expect(!workspace.hasPendingLifecycleOperations)
        try library.update(workspace.projectID) { $0.name = "An unrelated edit" }
        let current = try trash ? workspace.prepareTrash(posts) : workspace.prepareUnbind(rootID)
        #expect(current == updated)
    }

    @Test func sourceOnlyTrashLeavesEveryOwnerExplicitAndBlocksCreationWithoutFallback() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "source.md": "source", "fallback.md": "ancestor",
        ])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/owner")
        let child = try scratch.folder("notes/owner/child")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(root.appending(path: "fallback.md"), to: root)
        try workspace.assignTemplate(source, to: owner)
        let plan = try workspace.prepareTrash(source)
        #expect(plan.removedChoices.isEmpty)
        #expect(plan.brokenDependencies.count == 1)
        let trash = scratch.url.appending(path: "controlled-source-trash.md")
        workspace.lifecycleOperations.trash = { url in
            try FileManager.default.moveItem(at: url, to: trash)
            return trash
        }
        #expect(try workspace.confirmDestructiveOperation(plan) == .trashed)
        #expect(workspace.project?.templateAssignments.count == 2)
        let creation = try workspace.prepareDocument(in: child, filenamePattern: "Blocked")
        guard case .sourceFailure = workspace.createDocument(creation, naming: .edited("Blocked")) else {
            Issue.record("A missing nearer source must not fall back to its ancestor")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: child.appending(path: "Blocked.md").path))
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
