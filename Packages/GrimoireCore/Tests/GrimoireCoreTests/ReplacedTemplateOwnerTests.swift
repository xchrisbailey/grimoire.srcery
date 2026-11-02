import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct ReplacedTemplateOwnerTests {
    @Test(arguments: [false, true], [false, true])
    func anObservedRegularFileRetiresTheFolderChoiceWithoutTouchingItsReplacement(ancestor: Bool, useSource: Bool)
        async throws
    {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved source"])
        let owner = try scratch.folder("notes/area/posts").resolvingSymlinksInPath().standardizedFileURL
        let replacement = ancestor ? owner.deletingLastPathComponent() : owner
        let source = scratch.url.appending(path: "notes/source.md")
        if useSource {
            try workspace.assignTemplate(source, to: owner)
        } else {
            try workspace.disableTemplate(in: owner)
        }
        var inactive = try #require(try workspace.templateAssignment(for: owner))
        inactive.state = .unresolved
        try FileManager.default.removeItem(at: replacement)
        let bytes = Data("ordinary replacement must survive".utf8)
        try bytes.write(to: replacement)
        let identity = try LifecycleIdentity(replacement)
        workspace.refreshTemplateAssignments()
        #expect(workspace.project?.templateAssignments == [inactive])
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).project(workspace.projectID)?
                .templateAssignments == [inactive])
        #expect(try LifecycleIdentity(replacement) == identity)
        #expect(try Data(contentsOf: replacement) == bytes)
        try FileManager.default.removeItem(at: replacement)
        try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: true)
        workspace.refreshTemplateAssignments()
        #expect(try workspace.effectiveTemplateAssignment(for: owner) == nil)
        #expect(try workspace.templateAssignment(for: owner) == inactive)
        workspace.deactivate()
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let reopened = Workspace(projectID: workspace.projectID, library: relaunched)
        reopened.activate()
        defer { reopened.deactivate() }
        #expect(reopened.project?.templateAssignments == [inactive])
        #expect(try reopened.effectiveTemplateAssignment(for: owner) == nil)
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved source")
    }
}
