import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct DestructiveLifecycleTests {
    @Test func trashRemovesSubtreeChoicesButKeepsOtherRootsBrokenAndRestorationUnconfigured() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "posts/source.md": "saved\r\n", "posts/existing.md": "untouched",
        ])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        let archive = try scratch.folder("notes/posts/archive")
        let other = try scratch.folder("other")
        try library.bindFolder(other, to: workspace.projectID)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: posts)
        try workspace.disableTemplate(in: archive)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: other)
        let plan = try workspace.prepareTrash(posts)
        #expect(plan.removedChoices.count == 2)
        #expect(plan.brokenDependencies.count == 1)
        let before = library.projects
        #expect(try workspace.confirmDestructiveOperation(plan, confirmed: false) == .cancelled)
        #expect(library.projects == before)
        let trash = scratch.url.appending(path: "controlled-trash")
        workspace.lifecycleOperations.trash = { url in
            #expect(workspace.hasPendingLifecycleOperations)
            #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
            try FileManager.default.moveItem(at: url, to: trash)
            return trash
        }
        #expect(try workspace.confirmDestructiveOperation(plan) == .trashed)
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(workspace.project?.templateAssignments == plan.brokenDependencies)
        #expect(try Data(contentsOf: trash.appending(path: "source.md")) == Data("saved\r\n".utf8))
        #expect(try String(contentsOf: trash.appending(path: "existing.md"), encoding: .utf8) == "untouched")
        try FileManager.default.moveItem(at: trash, to: posts)
        #expect(try workspace.templateAssignment(for: posts) == nil)
        #expect(try workspace.templateAssignment(for: archive) == nil)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func confirmedUnbindRemovesOnlyOwnedChoicesAndRetainsBrokenDependencies() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "\u{FEFF}saved\r\n"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        let other = try scratch.folder("other")
        try library.bindFolder(other, to: workspace.projectID)
        try workspace.assignTemplate(source, to: root)
        try workspace.assignTemplate(source, to: other)
        let rootID = try #require(workspace.reference(for: root)?.rootID)
        let plan = try workspace.prepareUnbind(rootID)
        #expect(plan.removedChoices.count == 1)
        #expect(plan.brokenDependencies.count == 1)
        let before = library.projects
        #expect(try workspace.confirmDestructiveOperation(plan, confirmed: false) == .cancelled)
        #expect(library.projects == before)
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) {
            #expect(throws: (any Error).self) { try workspace.confirmDestructiveOperation(plan) }
            #expect(library.projects == before)
            #expect(workspace.folders.contains { $0.id == rootID && $0.url != nil })
        }
        #expect(try workspace.confirmDestructiveOperation(plan) == .completed)
        #expect(workspace.project?.root(rootID) == nil)
        #expect(workspace.project?.templateAssignments == plan.brokenDependencies)
        #expect(try Data(contentsOf: source) == Data("\u{FEFF}saved\r\n".utf8))
        let creation = try workspace.prepareDocument(in: other, filenamePattern: "New")
        guard case .sourceFailure = workspace.createDocument(creation, naming: .edited("Blocked")) else {
            Issue.record("An unbound source must remain an explicit broken choice")
            return
        }
        try library.bindFolder(root, to: workspace.projectID)
        #expect(try workspace.templateAssignment(for: root) == nil)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
