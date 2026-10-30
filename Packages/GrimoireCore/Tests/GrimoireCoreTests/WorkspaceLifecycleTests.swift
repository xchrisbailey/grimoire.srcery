import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct WorkspaceLifecycleTests {
    @Test func renameCarriesSubtreeChoicesAndEverySourceReferenceWithoutChangingBytes() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "{title}\r\n"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let child = try scratch.folder("notes/posts/archive")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: scratch.url.appending(path: "notes"))
        try workspace.assignTemplate(source, to: folder)
        try workspace.disableTemplate(in: child)
        let result = workspace.rename(folder, to: "drafts")
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        #expect(moved.lastPathComponent == "drafts")
        let sourceReference = try #require(workspace.reference(for: source))
        #expect(try workspace.templateAssignment(for: moved)?.choice == .useSource(sourceReference))
        #expect(try workspace.templateAssignment(for: moved.appending(path: "archive"))?.choice == .noTemplate)
        let renamedSource = workspace.rename(source, to: "template")
        #expect(renamedSource.error == nil)
        let sourceURL = try #require(renamedSource.movedURL)
        let renamedReference = try #require(workspace.reference(for: sourceURL))
        #expect(try workspace.templateAssignment(for: moved)?.choice == .useSource(renamedReference))
        #expect(
            try workspace.templateAssignment(for: scratch.url.appending(path: "notes"))?.choice
                == .useSource(renamedReference))
        #expect(try Data(contentsOf: sourceURL) == Data("{title}\r\n".utf8))
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func dragCarriesExplicitSubtreeAndSharedSourcesButRecomputesInheritedContent() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "source.md": "outer", "posts/source.md": "inner {title}",
        ])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = root.appending(path: "posts")
        let inherited = try scratch.folder("notes/posts/inherited")
        let archive = try scratch.folder("notes/posts/archive")
        let target = try scratch.folder("notes/target")
        let references = try scratch.folder("notes/references")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        try workspace.disableTemplate(in: target)
        try workspace.disableTemplate(in: archive)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: references)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: archive)
        let otherRoot = try scratch.folder("other")
        try library.bindFolder(otherRoot, to: workspace.projectID)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: otherRoot)
        let oldDocument = try scratch.file("notes/posts/existing.md", "unchanged {title}")
        let result = workspace.move(posts, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        #expect(!FileManager.default.fileExists(atPath: inherited.path))
        #expect(try workspace.templateAssignment(for: moved) == nil)
        #expect(
            try workspace.effectiveTemplateAssignment(for: moved.appending(path: "inherited"))?.choice == .noTemplate)
        let source = try #require(workspace.reference(for: moved.appending(path: "source.md")))
        #expect(try workspace.templateAssignment(for: references)?.choice == .useSource(source))
        #expect(try workspace.templateAssignment(for: moved.appending(path: "archive"))?.choice == .useSource(source))
        #expect(try workspace.templateAssignment(for: otherRoot)?.choice == .useSource(source))
        let creation = try workspace.prepareDocument(in: references, filenamePattern: "New")
        guard case .published(let document) = workspace.createDocument(creation, naming: .edited("Created")) else {
            Issue.record("Creation must use the relocated source")
            return
        }
        #expect(try String(contentsOf: document.url, encoding: .utf8) == "inner Created")
        #expect(
            try String(contentsOf: moved.appending(path: oldDocument.lastPathComponent), encoding: .utf8)
                == "unchanged {title}")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test(arguments: [false, true])
    func destinationRecordConflictStopsBeforeFilesystemChanges(rename: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source"])
        defer { workspace.deactivate() }
        let source = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/target")
        let destination = rename ? scratch.url.appending(path: "notes/drafts") : target.appending(path: "posts")
        let stale = try scratch.folder("notes/" + (rename ? "drafts" : "target/posts") + "/child")
        try workspace.disableTemplate(in: source)
        try workspace.disableTemplate(in: stale)
        try FileManager.default.removeItem(at: destination)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = rename ? workspace.rename(source, to: "drafts") : workspace.move(source, into: target)
        #expect(result.movedURL == nil)
        let explanation = result.error?.localizedDescription
        #expect(explanation == LifecycleError.conflict.localizedDescription, "\(String(describing: result.error))")
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
    }

    @Test(arguments: [false, true])
    func preparationAndFilesystemFailureRetainAssignmentsAndBytes(rename: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "preserved"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/target")
        try workspace.disableTemplate(in: folder)
        let before = library.projects
        let store = ProjectStore(fileURL: library.storageURL)
        let bytes = try Data(contentsOf: store.fileURL)
        try withBlockedWrites(to: store) { () throws in
            let result = rename ? workspace.rename(folder, to: "drafts") : workspace.move(folder, into: target)
            #expect(result.movedURL == nil)
            #expect(result.error != nil)
            #expect(library.projects == before)
            #expect(try Data(contentsOf: store.fileURL) == bytes)
        }
        workspace.lifecycleOperations.rename = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        workspace.lifecycleOperations.move = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let result = rename ? workspace.rename(folder, to: "drafts") : workspace.move(folder, into: target)
        #expect(result.movedURL == nil)
        #expect(result.error != nil)
        #expect(library.projects == before)
        #expect(ProjectLibrary(store: store).projects == before)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(try String(contentsOf: scratch.url.appending(path: "notes/source.md"), encoding: .utf8) == "preserved")
    }

    @Test(arguments: [false, true])
    func finalSaveFailureReturnsActualMoveAndRetainsDurableIntentUntilSameWindowRetry(rename: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved {filename}"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/target")
        let unrelated = try scratch.folder("notes/unrelated")
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: folder)
        let before = workspace.project?.templateAssignments
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        workspace.lifecycleOperations.rename = { url, name in
            let moved = try FileOperations.rename(url, to: name)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        workspace.lifecycleOperations.move = { url, destination in
            let moved = try FileOperations.move(url, into: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = rename ? workspace.rename(folder, to: "drafts") : workspace.move(folder, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error != nil)
        #expect(result.error?.localizedDescription.contains("item moved") == true)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(workspace.project?.templateAssignments == before)
        #expect(workspace.hasPendingLifecycleOperations)
        let store = ProjectStore(fileURL: library.storageURL)
        #expect(ProjectLibrary(store: store).projects == library.projects)
        workspace.reconcileLifecycleOperations()
        #expect(workspace.hasPendingLifecycleOperations)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(throws: (any Error).self) { try workspace.disableTemplate(in: moved) }
        #expect(throws: (any Error).self) { try workspace.inheritTemplate(in: moved) }
        #expect(workspace.rename(moved, to: "again").movedURL == nil)
        #expect(workspace.move(moved, into: unrelated).movedURL == nil)
        #expect(throws: (any Error).self) { try workspace.assignTemplate(source, to: moved) }
        #expect(throws: (any Error).self) { try library.bindFolder(moved, to: workspace.projectID) }
        #expect(throws: (any Error).self) { try library.deleteProject(workspace.projectID) }
        try workspace.disableTemplate(in: unrelated)
        try library.update(workspace.projectID) { $0.name = "Still editable" }
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(
            try workspace.templateAssignment(for: moved)?.choice
                == .useSource(try #require(workspace.reference(for: source))))
        #expect(try workspace.templateAssignment(for: unrelated)?.choice == .noTemplate)
        #expect(ProjectLibrary(store: store).projects == library.projects)
    }

    @Test func configuredBoundariesFailClosedWhileUnconfiguredCrossRootMoveRemainsAvailable() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source", "plain.md": "plain"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let target = try scratch.folder("target")
        let nested = try scratch.folder("notes/nested")
        let other = try library.bindFolder(target, to: workspace.projectID)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: nested)
        let before = library.projects
        #expect(workspace.move(nested, into: target).movedURL == nil)
        #expect(workspace.move(root.appending(path: "source.md"), into: target).movedURL == nil)
        #expect(workspace.rename(root, to: "another-root").movedURL == nil)
        let rootID = try #require(workspace.project?.roots.first?.id)
        #expect(throws: (any Error).self) { try workspace.unbind(rootID) }
        #expect(throws: (any Error).self) { try workspace.regrantAccess(to: rootID, with: target) }
        #expect(throws: (any Error).self) { try workspace.requireUnconfiguredLifecycleItem(nested) }
        #expect(library.projects == before)
        let plain = workspace.move(root.appending(path: "plain.md"), into: target)
        let moved = try #require(plain.movedURL)
        #expect(plain.error == nil)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "plain")
        #expect(workspace.reference(for: moved)?.rootID == other.id)
    }

}

@MainActor @Suite struct LifecyclePreflightTests {
    @Test(arguments: [false, true], [false, true])
    func occupiedDestinationFailsPreparationWithoutLeavingUnnecessaryRepair(rename: Bool, caseAlias: Bool) async throws
    {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("notes/target")
        let destinationPath = rename ? "notes/drafts" : "notes/target/posts"
        let competitorPath = caseAlias ? (rename ? "notes/DRAFTS" : "notes/target/POSTS") : destinationPath
        let competitor = try scratch.file(competitorPath + "/keep.md", "competitor")
        if !FileManager.default.fileExists(atPath: scratch.url.appending(path: destinationPath).path) {
            try scratch.file(destinationPath + "/keep.md", "competitor")
        }
        try workspace.disableTemplate(in: source)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = rename ? workspace.rename(source, to: "drafts") : workspace.move(source, into: target)
        #expect(result.movedURL == nil)
        #expect(result.error != nil)
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try String(contentsOf: source.appending(path: "keep.md"), encoding: .utf8) == "original")
        #expect(try String(contentsOf: competitor, encoding: .utf8) == "competitor")
    }

    @Test func caseOnlySourceRenameRemainsRecoverableWithoutRewritingContent() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "{title}\r\n"])
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/owner")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: owner)
        var interrupted = Data()
        workspace.lifecycleOperations.rename = { url, name in
            interrupted = try Data(contentsOf: library.storageURL)
            return try FileOperations.rename(url, to: name)
        }
        let result = workspace.rename(source, to: "SOURCE")
        #expect(result.error == nil)
        let moved = try #require(result.movedURL)
        #expect(moved.lastPathComponent == "SOURCE.md")
        workspace.deactivate()
        try interrupted.write(to: library.storageURL, options: .atomic)
        let restarted = Workspace(
            projectID: workspace.projectID,
            library: ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)))
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(!restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError == nil)
        let rootID = try #require(restarted.project?.roots.first?.id)
        #expect(
            try restarted.templateAssignment(for: owner)?.choice
                == .useSource(
                    FileReference(rootID: rootID, relativePath: "SOURCE.md")))
        #expect(try String(contentsOf: moved, encoding: .utf8) == "{title}\r\n")
    }
}
