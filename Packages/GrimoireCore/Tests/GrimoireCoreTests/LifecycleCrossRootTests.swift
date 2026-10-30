import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleCrossRootTests {
    @Test func configuredSubtreeAndSharedSourcesFollowTheMostSpecificDestinationRoot() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "posts/source.md": "saved {title}\r\n", "posts/existing.md": "unchanged {title}",
        ])
        defer { workspace.deactivate() }
        let posts = scratch.url.appending(path: "notes/posts")
        let archive = try scratch.folder("notes/posts/archive")
        let owner = try scratch.folder("notes/owner")
        let outer = try scratch.folder("destination")
        let target = try scratch.folder("destination/inner")
        try library.bindFolder(outer, to: workspace.projectID)
        let destinationRoot = try library.bindFolder(target, to: workspace.projectID)
        let source = posts.appending(path: "source.md")
        try workspace.assignTemplate(source, to: posts)
        try workspace.disableTemplate(in: archive)
        try workspace.assignTemplate(source, to: owner)
        try workspace.assignTemplate(source, to: outer)
        let result = workspace.move(posts, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        #expect(result.legacyMovedURL == nil)
        let reference = FileReference(rootID: destinationRoot.id, relativePath: "posts/source.md")
        #expect(try workspace.templateAssignment(for: moved)?.owner.rootID == destinationRoot.id)
        #expect(try workspace.templateAssignment(for: moved)?.choice == .useSource(reference))
        #expect(try workspace.templateAssignment(for: moved.appending(path: "archive"))?.choice == .noTemplate)
        #expect(try workspace.templateAssignment(for: owner)?.choice == .useSource(reference))
        #expect(try workspace.templateAssignment(for: outer)?.choice == .useSource(reference))
        let plan = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        guard case .published(let document) = workspace.createDocument(plan, naming: .edited("Created")) else {
            Issue.record("Creation must read the relocated shared source")
            return
        }
        #expect(try Data(contentsOf: document.url) == Data("saved Created\r\n".utf8))
        #expect(try String(contentsOf: moved.appending(path: "existing.md"), encoding: .utf8) == "unchanged {title}")
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test(arguments: [false, true])
    func inheritedOnlySubtreeUsesDestinationBoundaryWithoutCopyingTheOldChoice(innerBound: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "old"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let posts = try scratch.folder("notes/posts/child").deletingLastPathComponent()
        let outer = try scratch.folder("destination")
        let target = try scratch.folder("destination/inner")
        let source = try scratch.file("destination/source.md", "new {title}")
        try library.bindFolder(outer, to: workspace.projectID)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        try workspace.assignTemplate(source, to: outer)
        if innerBound { try library.bindFolder(target, to: workspace.projectID) }
        let before = workspace.project?.templateAssignments
        var intent = Data()
        workspace.lifecycleOperations.move = { url, destination in
            intent = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: destination)
        }
        let result = workspace.move(posts, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        #expect(workspace.project?.templateAssignments == before)
        #expect(try workspace.templateAssignment(for: moved) == nil)
        let plan = try workspace.prepareDocument(in: moved.appending(path: "child"), filenamePattern: "New")
        #expect((plan.assignment == nil) == innerBound)
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Literal {date}")) else {
            Issue.record("Destination inheritance must be recomputed without introducing an explicit choice")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == (innerBound ? "" : "new Literal {date}"))
        #expect(!intent.isEmpty)
        workspace.deactivate()
        try intent.write(to: library.storageURL, options: .atomic)
        let restarted = Workspace(
            projectID: workspace.projectID, library: ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)))
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(!restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError == nil)
        #expect(restarted.project?.templateAssignments == before)
    }

    @Test func movingSharedSourceRequiresReviewAndPreservesLiteralName() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved {title}"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder("destination")
        try library.bindFolder(target, to: workspace.projectID)
        let source = scratch.url.appending(path: "notes/source.md")
        try workspace.assignTemplate(source, to: owner)
        let plan = try workspace.prepareDocument(in: owner, filenamePattern: "Generated")
        let result = workspace.move(source, into: target)
        #expect(result.error == nil)
        let moved = try #require(result.movedURL)
        guard case .reviewNeeded(let reviewed) = workspace.createDocument(plan, naming: .edited("Keep {date}")) else {
            Issue.record("A source's cross-root reference change requires review before creation")
            return
        }
        #expect(reviewed.assignment?.choice == .useSource(try #require(workspace.reference(for: moved))))
        #expect(!FileManager.default.fileExists(atPath: owner.appending(path: "Keep {date}.md").path))
        guard case .published(let created) = workspace.createDocument(reviewed, naming: .edited("Keep {date}")) else {
            Issue.record("Review must preserve the edited literal name")
            return
        }
        #expect(created.url.lastPathComponent == "Keep {date}.md")
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "saved Keep {date}")
    }
}
