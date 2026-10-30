import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateEligibilityTests {
    @Test func invalidSelectionsNeverReplaceTheSavedChoice() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "keep"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        let directory = try scratch.folder("notes/directory.md")
        let notMarkdown = try scratch.file("notes/plain.txt", "text")
        let sibling = try scratch.file("notes-other/source.md", "outside")
        let traversal = URL(fileURLWithPath: root.path + "/../notes/source.md")
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        for invalid in [directory, notMarkdown, sibling, traversal] {
            #expect(throws: (any Error).self) { try workspace.assignTemplate(invalid, to: root) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(try Data(contentsOf: source) == Data("keep".utf8))
    }

    @Test(arguments: [Data([0xC3, 0x28]), Data([0xFF, 0xFE, 0x41]), Data([0x61, 0, 0x62])])
    func invalidSavedTextIsNotDecodedLossily(bytes: Data) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "valid"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(folder.appending(path: "source.md"), to: folder)
        let bad = folder.appending(path: "bad.md")
        try bytes.write(to: bad)
        let before = library.projects
        #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(bad, to: folder) }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: bad) == bytes)
    }

    @Test func savedTextAllowsEmptyBOMLineEndingsAndMalformedYAMLWithoutRewriting() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace()
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        for text in ["", "\u{FEFF}---\r\ninvalid: [\r  body \n\tend"] {
            let source = try scratch.file("notes/source.md", text)
            try workspace.assignTemplate(source, to: root)
            let assignment = try #require(try workspace.templateAssignment(for: root))
            #expect(try workspace.templateSourceURL(for: assignment) == source)
            #expect(try Data(contentsOf: source) == Data(text.utf8))
        }
    }

    @Test func symlinkTargetsMustBeInsideThisActiveProjectsAccessibleRoots() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "keep"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let templates = try scratch.folder("templates")
        let target = try scratch.file("templates/base.md", "reusable")
        let link = root.appending(path: "link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        let before = library.projects

        // Another project's binding cannot make this project's link eligible.
        let other = try library.createProject(named: "Other")
        try library.bindFolder(templates, to: other.id)
        #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(link, to: root) }
        #expect(library.project(workspace.projectID) == before.first)

        let binding = try library.bindFolder(templates, to: workspace.projectID)
        workspace.sync()
        try workspace.assignTemplate(link, to: root)
        let assignment = try #require(try workspace.templateAssignment(for: root))
        #expect(assignment.choice == .useSource(FileReference(rootID: binding.id, relativePath: "base.md")))
        #expect(try workspace.templateSourceURL(for: assignment) == target)

        // A decoded, syntactically valid reference must recheck the current link target.
        let storedLink = FolderTemplateAssignment(
            owner: assignment.owner,
            choice: .useSource(FileReference(rootID: assignment.owner.rootID, relativePath: "link.md")))
        let outside = try scratch.file("outside/base.md", "outside")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: TemplateAssignmentError.self) { try workspace.templateSourceURL(for: storedLink) }
        #expect(try Data(contentsOf: target) == Data("reusable".utf8))
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    @Test func inactiveWorkspaceAndUnresolvableBookmarksCannotUseLastKnownPaths() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        let root = scratch.url.appending(path: "notes")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        let assignment = try #require(try workspace.templateAssignment(for: root))
        workspace.deactivate()
        #expect(throws: TemplateAssignmentError.self) { try workspace.templateSourceURL(for: assignment) }
        #expect(throws: TemplateAssignmentError.self) {
            try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        }
        try library.update(workspace.projectID) { $0.roots[0].bookmark = Data([0xFF]) }
        let relaunched = Workspace(projectID: workspace.projectID, library: library)
        relaunched.activate()
        defer { relaunched.deactivate() }
        #expect(relaunched.folders.first?.status == .needsAccess)
        #expect(throws: TemplateAssignmentError.self) { try relaunched.templateSourceURL(for: assignment) }
        #expect(library.project(workspace.projectID)?.templateAssignments == [assignment])
    }

    @Test func unreadableSourceAndMissingOwnerKeepPreviousAssignment() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "keep", "blocked.md": "blocked"])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let source = scratch.url.appending(path: "notes/source.md")
        let blocked = scratch.url.appending(path: "notes/blocked.md")
        try workspace.assignTemplate(source, to: folder)
        let before = library.projects
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: blocked.path)
            } catch {
                Issue.record(error)
            }
        }
        #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(blocked, to: folder) }
        try FileManager.default.removeItem(at: folder)
        #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(source, to: folder) }
        #expect(library.projects == before)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
    }
}
