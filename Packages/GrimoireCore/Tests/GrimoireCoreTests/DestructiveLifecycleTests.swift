import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DestructiveLifecycleTests {
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
