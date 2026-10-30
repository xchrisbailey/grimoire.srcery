import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateAssignmentTests {
    @Test func exactChoiceSurvivesRelaunchWithoutCopyingSource() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "---\r\nnot: [yaml\r\n"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let source = scratch.url.appending(path: "notes/source.md")
        let original = try Data(contentsOf: source)

        try workspace.assignTemplate(source, to: folder)
        let choice = try #require(try workspace.templateAssignment(for: folder))
        #expect(choice.owner.relativePath == "posts")
        #expect(choice.choice == .useSource(FileReference(rootID: choice.owner.rootID, relativePath: "source.md")))
        #expect(try workspace.templateAssignment(for: scratch.url.appending(path: "notes")) == nil)
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.project(workspace.projectID)?.templateAssignments == [choice])
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
