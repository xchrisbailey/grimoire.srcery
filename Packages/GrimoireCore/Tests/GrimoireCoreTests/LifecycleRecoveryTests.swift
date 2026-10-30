import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleRecoveryTests {
    @Test func replacedSourceDuringMoveCannotCommitConfigurationForTheWrongItem() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/source.md")
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder("notes/target")
        let preserved = scratch.url.appending(path: "preserved.md")
        try workspace.assignTemplate(source, to: owner)
        let before = workspace.project?.templateAssignments
        workspace.lifecycleOperations.move = { url, destination in
            try FileManager.default.moveItem(at: url, to: preserved)
            try Data("replacement".utf8).write(to: url)
            return try FileOperations.move(url, into: destination)
        }
        let result = workspace.move(source, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(workspace.project?.templateAssignments == before)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "original")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "replacement")
        try FileManager.default.moveItem(at: moved, to: scratch.url.appending(path: "replacement.md"))
        try FileManager.default.moveItem(at: preserved, to: moved)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
        let reference = try #require(workspace.reference(for: moved))
        #expect(try workspace.templateAssignment(for: owner)?.choice == .useSource(reference))
    }

    @Test(arguments: [false, true], [false, true])
    func restartReconcilesOnlyObservedPreOrPostMove(rename: Bool, completed: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "saved {title}"])
        let folder = scratch.url.appending(path: "notes/posts")
        let target = try scratch.folder("notes/target")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: owner)
        let before = workspace.project?.templateAssignments
        var interrupted = Data()
        workspace.lifecycleOperations.rename = { url, name in
            interrupted = try Data(contentsOf: library.storageURL)
            if completed { return try FileOperations.rename(url, to: name) }
            throw CocoaError(.userCancelled)
        }
        workspace.lifecycleOperations.move = { url, destination in
            interrupted = try Data(contentsOf: library.storageURL)
            if completed { return try FileOperations.move(url, into: destination) }
            throw CocoaError(.userCancelled)
        }
        _ = rename ? workspace.rename(folder, to: "drafts") : workspace.move(folder, into: target)
        workspace.deactivate()
        try interrupted.write(to: library.storageURL, options: .atomic)
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.loadError == nil)
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        #expect(restarted.hasPendingLifecycleOperations)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(!restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError == nil)
        if completed {
            let moved = rename ? scratch.url.appending(path: "notes/drafts") : target.appending(path: "posts")
            let source = try #require(restarted.reference(for: moved.appending(path: "source.md")))
            #expect(try restarted.templateAssignment(for: moved)?.choice == .useSource(source))
            #expect(try restarted.templateAssignment(for: owner)?.choice == .useSource(source))
            #expect(try String(contentsOf: moved.appending(path: "source.md"), encoding: .utf8) == "saved {title}")
        } else {
            #expect(restarted.project?.templateAssignments == before)
            #expect(FileManager.default.fileExists(atPath: folder.path))
        }
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == relaunched.projects)
    }

    @Test func ambiguousRestartPreservesIntentAndBlocksRepairUntilManualFilesystemRepair() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original bytes"])
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/owner")
        let source = root.appending(path: "source.md")
        let target = try scratch.folder("notes/target")
        try workspace.assignTemplate(source, to: owner)
        let creation = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        let before = workspace.project?.templateAssignments
        var interrupted = Data()
        workspace.lifecycleOperations.move = { url, destination in
            interrupted = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: destination)
        }
        let moved = try #require(workspace.move(source, into: target).movedURL)
        workspace.deactivate()
        try interrupted.write(to: library.storageURL, options: .atomic)
        try scratch.file("notes/source.md", "unrelated replacement")
        let store = ProjectStore(fileURL: library.storageURL)
        let relaunched = ProjectLibrary(store: store)
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError != nil)
        #expect(restarted.project?.templateAssignments == before)
        #expect(try Data(contentsOf: store.fileURL) == interrupted)
        #expect(throws: (any Error).self) { try restarted.assignTemplate(moved, to: owner) }
        #expect(throws: (any Error).self) { try restarted.disableTemplate(in: owner) }
        #expect(throws: (any Error).self) { try restarted.inheritTemplate(in: owner) }
        #expect(restarted.rename(source, to: "another").movedURL == nil)
        if case .failed = restarted.repairDocumentTemplate(creation, replacement: moved) {
        } else {
            Issue.record("Source recovery must not overwrite an assignment with pending lifecycle intent")
        }
        #expect(try String(contentsOf: moved, encoding: .utf8) == "original bytes")
        #expect(try String(contentsOf: source, encoding: .utf8) == "unrelated replacement")
        try FileManager.default.removeItem(at: source)
        restarted.reconcileLifecycleOperations()
        #expect(!restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError == nil)
        let reference = try #require(restarted.reference(for: moved))
        #expect(try restarted.templateAssignment(for: owner)?.choice == .useSource(reference))
        #expect(ProjectLibrary(store: store).projects == relaunched.projects)
    }

    @Test(arguments: ["destination", "parent", "unavailable root", "invalid identity", "null records"])
    func uncertainOrInvalidRestartNeverDiscardsIntent(scenario: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "unchanged"])
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        let target = try scratch.folder("notes/target")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(source, to: owner)
        var interrupted = Data()
        workspace.lifecycleOperations.move = { url, destination in
            interrupted = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: destination)
        }
        let moved = try #require(workspace.move(source, into: target).movedURL)
        workspace.deactivate()
        interrupted = try uncertainSnapshot(
            scenario, scratch: scratch, moved: moved,
            store: ProjectStore(fileURL: library.storageURL), interrupted: interrupted)
        try interrupted.write(to: library.storageURL, options: .atomic)
        let store = ProjectStore(fileURL: library.storageURL)
        let relaunched = ProjectLibrary(store: store)
        if scenario == "invalid identity" || scenario == "null records" {
            #expect(relaunched.loadError != nil)
            #expect(throws: (any Error).self) { try relaunched.createProject(named: "Must not overwrite") }
        } else {
            #expect(relaunched.loadError == nil)
            let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
            restarted.activate()
            defer { restarted.deactivate() }
            #expect(restarted.hasPendingLifecycleOperations)
            #expect(restarted.lastError != nil)
            let rootID = try #require(restarted.project?.roots.first?.id)
            #expect(throws: (any Error).self) { try restarted.unbind(rootID) }
        }
        #expect(try Data(contentsOf: store.fileURL) == interrupted)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "unchanged")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    private func uncertainSnapshot(
        _ scenario: String, scratch: Scratch, moved: URL,
        store: ProjectStore, interrupted: Data
    ) throws -> Data {
        let backup = scratch.url.appending(path: "original")
        let target = moved.deletingLastPathComponent()
        switch scenario {
        case "destination":
            try FileManager.default.moveItem(at: moved, to: backup)
            try scratch.file("notes/target/source.md", "unchanged")
        case "parent":
            try FileManager.default.moveItem(at: target, to: backup)
            try scratch.folder("notes/target")
            try FileManager.default.moveItem(at: backup.appending(path: "source.md"), to: moved)
        case "unavailable root":
            // Corrupt only bookmark access; the still-existing last-known path is not evidence.
            try interrupted.write(to: store.fileURL, options: .atomic)
            var projects = try store.load()
            projects[0].roots[0].bookmark = Data([0])
            try store.save(projects)
            return try Data(contentsOf: store.fileURL)
        case "invalid identity":
            return Data(
                try #require(String(data: interrupted, encoding: .utf8))
                    .replacingOccurrences(of: "\"type\" : 32768", with: "\"type\" : 0").utf8)
        default:
            return Data(
                try #require(String(data: interrupted, encoding: .utf8))
                    .replacingOccurrences(
                        of: "\"pendingLifecycleOperations\" : [",
                        with: "\"pendingLifecycleOperations\" : null, \"ignored\" : ["
                    ).utf8)
        }
        return interrupted
    }
}
