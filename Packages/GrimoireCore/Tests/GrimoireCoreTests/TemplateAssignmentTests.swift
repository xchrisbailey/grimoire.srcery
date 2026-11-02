import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct TemplateAssignmentTests {
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

    @Test func unavailableSourceReportsActionableFailureAndRetainsChoice() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let before = library.projects
        do {
            try workspace.assignTemplate(folder.appending(path: "missing.md"), to: folder)
            Issue.record("A missing source must fail")
        } catch {
            #expect(error is TemplateAssignmentError)
            #expect(error.localizedDescription.contains("choose another source"))
        }
        #expect(library.projects == before)
    }

    @Test func cancellationAndFailedCommitKeepBothWindowsAndRelaunchOnOldChoice() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["first.md": "first", "second.md": "second"])
        let other = Workspace(projectID: workspace.projectID, library: library)
        other.activate()
        defer {
            workspace.deactivate()
            other.deactivate()
        }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "first.md"), to: folder)
        let before = library.projects
        let store = ProjectStore(fileURL: library.storageURL)
        let bytes = try Data(contentsOf: store.fileURL)
        try workspace.assignTemplate(nil, to: folder)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        try withBlockedWrites(to: store) { () throws in
            #expect(throws: (any Error).self) {
                try workspace.assignTemplate(folder.appending(path: "second.md"), to: folder)
            }
            #expect(try other.templateAssignment(for: folder) == workspace.templateAssignment(for: folder))
            #expect(library.projects == before)
            #expect(try Data(contentsOf: store.fileURL) == bytes)
            #expect(ProjectLibrary(store: store).projects == before)
        }
        try other.assignTemplate(folder.appending(path: "second.md"), to: folder)
        #expect(library.projects != before)
        #expect(ProjectLibrary(store: store).projects == library.projects)
    }

    @Test func projectsSharingFoldersKeepIndependentReusableChoices() async throws {
        let scratch = try Scratch()
        let (first, library) = try await scratch.workspace(files: ["source.md": "shared"])
        let project = try library.createProject(named: "Other")
        let rootURL = scratch.url.appending(path: "notes")
        try library.bindFolder(rootURL, to: project.id)
        let second = Workspace(projectID: project.id, library: library)
        second.activate()
        defer {
            first.deactivate()
            second.deactivate()
        }
        let posts = try scratch.folder("notes/posts")
        let source = rootURL.appending(path: "source.md")
        try first.assignTemplate(source, to: rootURL)
        try first.assignTemplate(source, to: posts)
        #expect(try second.templateAssignment(for: rootURL) == nil)
        try second.assignTemplate(source, to: posts)
        #expect(library.project(first.projectID)?.templateAssignments.count == 2)
        #expect(library.project(second.projectID)?.templateAssignments.count == 1)
        #expect(try second.templateAssignment(for: rootURL) == nil)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func mostSpecificRootAndProjectOrderDetermineExactOwner() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source"])
        defer { workspace.deactivate() }
        let outer = try #require(workspace.folders.first?.id)
        let posts = try scratch.folder("notes/posts")
        let inner = try library.bindFolder(posts, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: posts)
        let choice = try #require(try workspace.templateAssignment(for: posts))
        #expect(choice.owner == FileReference(rootID: inner.id, relativePath: ""))
        #expect(choice.choice == .useSource(FileReference(rootID: outer, relativePath: "source.md")))

        let alias = FolderRoot(
            name: "Alias", bookmark: inner.bookmark, lastKnownPath: inner.lastKnownPath)
        try library.update(workspace.projectID) { $0.roots.append(alias) }
        workspace.sync()
        #expect(try workspace.templateAssignment(for: posts) == choice)
        try library.update(workspace.projectID) { $0.roots.swapAt(1, 2) }
        workspace.sync()
        #expect(try workspace.templateAssignment(for: posts) == nil)
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: posts)
        #expect(try workspace.templateAssignment(for: posts)?.owner.rootID == alias.id)
    }
}
