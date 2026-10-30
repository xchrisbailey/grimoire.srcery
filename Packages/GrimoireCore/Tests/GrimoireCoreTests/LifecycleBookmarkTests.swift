import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleBookmarkTests {
    @Test(arguments: [false, true])
    func authoritativeBookmarkUpdateIsAllowedUnlessItConflictsWithPendingIntent(pending: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/owner")
        let unrelated = try scratch.folder("notes/unrelated")
        let replacement = try scratch.folder("replacement")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        if pending { try leavePendingRename(source, workspace: workspace, library: library) }
        let rootID = try #require(workspace.folders.first?.id)
        let accessedURL = try #require(workspace.folders.first?.url)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        if pending {
            #expect(throws: (any Error).self) {
                try library.replaceBookmark(of: rootID, in: workspace.projectID, with: replacement)
            }
            let bookmark = try FolderBookmark.make(for: replacement)
            #expect(throws: (any Error).self) {
                try library.update(workspace.projectID) { $0.roots[0].bookmark = bookmark }
            }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
            #expect(workspace.hasPendingLifecycleOperations)
            #expect(workspace.isActive)
            #expect(workspace.folders.first?.url == accessedURL)
            let plan = try workspace.prepareDocument(in: unrelated, filenamePattern: "Still accessible")
            guard case .published(let document) = workspace.createDocument(plan, naming: .generated) else {
                Issue.record("A rejected bookmark edit must keep bound-root access usable")
                return
            }
            #expect(try Data(contentsOf: document.url).isEmpty)
            try workspace.setAlias("Alias", of: rootID)
        } else {
            try library.replaceBookmark(of: rootID, in: workspace.projectID, with: replacement)
            #expect(library.project(workspace.projectID)?.templateAssignments == before.first?.templateAssignments)
            workspace.sync()
            #expect(workspace.folders.first?.url?.resolvingSymlinksInPath() == replacement.resolvingSymlinksInPath())
        }
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func directAssignmentThroughAnEquivalentRootCannotBypassPendingPathProtection() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/owner")
        try scratch.folder("notes/unrelated")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        let root = try #require(workspace.project?.roots.first)
        let alias = FolderRoot(name: "Alias", bookmark: root.bookmark, lastKnownPath: root.lastKnownPath)
        try library.update(workspace.projectID) { $0.roots.append(alias) }
        try leavePendingRename(source, workspace: workspace, library: library)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let assignment = FolderTemplateAssignment(
            owner: FileReference(rootID: alias.id, relativePath: "unrelated"),
            choice: .useSource(FileReference(rootID: alias.id, relativePath: "renamed.md")))
        #expect(throws: (any Error).self) {
            try library.update(workspace.projectID) { $0.templateAssignments.append(assignment) }
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(workspace.hasPendingLifecycleOperations)
    }

    private func leavePendingRename(_ source: URL, workspace: Workspace, library: ProjectLibrary) throws {
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.rename = { url, name in
            let moved = try FileOperations.rename(url, to: name)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = workspace.rename(source, to: "renamed")
        #expect(result.movedURL != nil)
        #expect(result.error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
    }
}
