import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct LifecycleCrossRootRecoveryTests {
    @Test func unconfiguredCrossRootMoveWritesNoRecordSoLaterRewritesStaySavable() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("destination")
        try library.bindFolder(target, to: workspace.projectID)
        let directory = library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let bytes = try Data(contentsOf: library.storageURL)
        // Settings become unwritable right after the physical move, as in a failed final save.
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = workspace.move(posts, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(workspace.lifecycleRepairURLs.isEmpty)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        // An editor's atomic save replaces the inode; no record may exist to hold that save.
        let document = moved.appending(path: "keep.md")
        try Data("edited".utf8).write(to: document, options: .atomic)
        try workspace.authorizeDocumentSave(at: document)
        #expect(try String(contentsOf: document, encoding: .utf8) == "edited")
    }

    @Test(arguments: [false, true])
    func storedEmptyBeforeCrossRootRecordsStillReconcile(completed: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/keep.md": "original"])
        let posts = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("destination")
        let targetRoot = try library.bindFolder(target, to: workspace.projectID)
        let sourceRoot = try #require(workspace.project?.roots.first?.id)
        let operation = PendingLifecycleOperation(
            id: UUID(), projectID: workspace.projectID,
            source: FileReference(rootID: sourceRoot, relativePath: "posts"),
            destination: FileReference(rootID: targetRoot.id, relativePath: "posts"),
            rootIdentity: try LifecycleIdentity(posts.deletingLastPathComponent()),
            itemIdentity: try LifecycleIdentity(posts),
            sourceParentIdentity: try LifecycleIdentity(posts.deletingLastPathComponent()),
            destinationParentIdentity: try LifecycleIdentity(target), before: [], after: [],
            destinationRootIdentity: try LifecycleIdentity(target), sourceProjections: nil)
        try library.update(workspace.projectID) { $0.pendingLifecycleOperations.append(operation) }
        workspace.deactivate()
        if completed { try FileManager.default.moveItem(at: posts, to: target.appending(path: "posts")) }
        let restarted = Workspace(
            projectID: workspace.projectID, library: ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)))
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.lastError == nil)
        #expect(!restarted.hasPendingLifecycleOperations)
    }

    @Test(arguments: [false, true])
    func restartCompletesOnlyTheObservedOriginalItemAcrossBothRoots(completed: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "saved"])
        let posts = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("destination")
        let targetRoot = try library.bindFolder(target, to: workspace.projectID)
        try workspace.assignTemplate(posts.appending(path: "source.md"), to: posts)
        try library.update(workspace.projectID) {
            $0.lastOpenedFile = workspace.reference(for: posts.appending(path: "source.md"))
        }
        let before = workspace.project?.templateAssignments
        var intent = Data()
        workspace.lifecycleOperations.move = { url, destination in
            intent = try Data(contentsOf: library.storageURL)
            if completed { return try FileOperations.move(url, into: destination) }
            throw CocoaError(.userCancelled)
        }
        _ = workspace.move(posts, into: target)
        workspace.deactivate()
        try intent.write(to: library.storageURL, options: .atomic)
        let store = ProjectStore(fileURL: library.storageURL)
        let relaunched = ProjectLibrary(store: store)
        #expect(relaunched.loadError == nil)
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.lastError == nil)
        #expect(!restarted.hasPendingLifecycleOperations)
        if completed {
            let moved = target.appending(path: "posts")
            let reference = FileReference(rootID: targetRoot.id, relativePath: "posts/source.md")
            #expect(try restarted.templateAssignment(for: moved)?.choice == .useSource(reference))
            #expect(restarted.project?.lastOpenedFile == reference)
            #expect(try String(contentsOf: moved.appending(path: "source.md"), encoding: .utf8) == "saved")
        } else {
            #expect(restarted.project?.templateAssignments == before)
            #expect(FileManager.default.fileExists(atPath: posts.path))
        }
        #expect(ProjectLibrary(store: store).projects == relaunched.projects)
    }

    @Test(arguments: ["source root", "destination root", "destination parent", "both locations", "wrong item"])
    func uncertainRestartRetainsBothRootReservationsWithoutReplaying(scenario: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        let source = scratch.url.appending(path: "notes/source.md")
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder("destination/target")
        let targetRoot = try library.bindFolder(target.deletingLastPathComponent(), to: workspace.projectID)
        try workspace.assignTemplate(source, to: owner)
        let before = workspace.project?.templateAssignments
        var intent = Data()
        workspace.lifecycleOperations.move = { url, destination in
            intent = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: destination)
        }
        let moved = try #require(workspace.move(source, into: target).movedURL)
        workspace.deactivate()
        let store = ProjectStore(fileURL: library.storageURL)
        try intent.write(to: store.fileURL, options: .atomic)
        try makeUncertain(scenario, scratch: scratch, store: store, destinationRootID: targetRoot.id, moved: moved)
        let bytes = try Data(contentsOf: store.fileURL)
        let relaunched = ProjectLibrary(store: store)
        #expect(relaunched.loadError == nil)
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError != nil)
        #expect(restarted.project?.templateAssignments == before)
        #expect(throws: (any Error).self) { try restarted.authorizeDocumentSave(at: moved) }
        #expect(throws: (any Error).self) { try restarted.authorizeDocumentSave(at: source) }
        #expect(throws: (any Error).self) {
            try relaunched.replaceBookmark(
                of: targetRoot.id, in: workspace.projectID, with: scratch.folder("replacement"))
        }
        restarted.reconcileLifecycleOperations()
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        #expect(
            try String(contentsOf: moved, encoding: .utf8) == (scenario == "wrong item" ? "replacement" : "original"))
    }

    private func makeUncertain(
        _ scenario: String, scratch: Scratch, store: ProjectStore, destinationRootID: UUID, moved: URL
    ) throws {
        if scenario == "source root" || scenario == "destination root" {
            var projects = try store.load()
            let id = scenario == "source root" ? try #require(projects.first?.roots.first?.id) : destinationRootID
            let index = try #require(projects[0].roots.firstIndex { $0.id == id })
            projects[0].roots[index].bookmark = Data([0])
            try store.save(projects)
        } else if scenario == "destination parent" {
            let original = scratch.url.appending(path: "original-parent")
            try FileManager.default.moveItem(at: moved.deletingLastPathComponent(), to: original)
            try scratch.folder("destination/target")
            try FileManager.default.moveItem(at: original.appending(path: "source.md"), to: moved)
        } else if scenario == "both locations" {
            try scratch.file("notes/source.md", "replacement")
        } else {
            try FileManager.default.moveItem(at: moved, to: scratch.url.appending(path: "preserved.md"))
            try scratch.file("destination/target/source.md", "replacement")
        }
    }
}
