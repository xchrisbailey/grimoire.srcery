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
}
