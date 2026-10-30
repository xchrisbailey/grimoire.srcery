import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleReferenceTests {
    @Test func unresolvedAliasRemainsInactiveDuringUnrelatedAndContainingSubtreeMoves() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["plain.md": "untouched"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/target")
        let rootID = try #require(workspace.folders.first?.id)
        let alias = folder.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let inactive = FolderTemplateAssignment(
            owner: FileReference(rootID: rootID, relativePath: "posts/alias"), choice: .noTemplate, state: .unresolved)
        try library.update(workspace.projectID) { $0.templateAssignments = [inactive] }
        let plain = scratch.url.appending(path: "notes/plain.md")
        let renamed = workspace.rename(plain, to: "renamed")
        #expect(renamed.error == nil)
        #expect(workspace.project?.templateAssignments == [inactive])
        let result = workspace.move(folder, into: target)
        #expect(result.error == nil)
        let moved = try #require(result.movedURL)
        let expected = FolderTemplateAssignment(
            owner: FileReference(rootID: rootID, relativePath: "target/posts/alias"),
            choice: .noTemplate, state: .unresolved)
        #expect(workspace.project?.templateAssignments == [expected])
        #expect(try workspace.effectiveTemplateAssignment(for: moved) == nil)
        #expect(try String(contentsOf: #require(renamed.movedURL), encoding: .utf8) == "untouched")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
