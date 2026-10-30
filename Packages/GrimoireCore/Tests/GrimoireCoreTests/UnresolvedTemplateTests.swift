import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct UnresolvedTemplateTests {
    @Test func missingOwnerStaysInactiveAfterReappearanceAndRelaunch() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: owner)
        let original = try #require(workspace.project?.templateAssignments.first)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        var inactive = original
        inactive.state = .unresolved
        #expect(workspace.project?.templateAssignments == [inactive])
        try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: true)
        workspace.refreshTemplateAssignments()
        #expect(try workspace.effectiveTemplateAssignment(for: owner) == nil)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let reopened = Workspace(projectID: workspace.projectID, library: restarted)
        reopened.activate()
        defer { reopened.deactivate() }
        #expect(reopened.project?.templateAssignments == [inactive])
        #expect(try reopened.effectiveTemplateAssignment(for: owner) == nil)
    }
}
