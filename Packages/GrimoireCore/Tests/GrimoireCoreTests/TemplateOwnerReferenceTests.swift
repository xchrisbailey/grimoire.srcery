import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct TemplateOwnerReferenceTests {
    @Test(arguments: [false, true])
    func decodedActiveOwnerAliasBlocksInspectionAndAssignmentWithoutChangingSettings(conflicting: Bool) throws {
        let fixture = try TemplateOwnerFixture()
        var assignments = [
            FolderTemplateAssignment(
                owner: fixture.reference("alias"), choice: .useSource(fixture.reference("base.md")))
        ]
        if conflicting {
            assignments.append(FolderTemplateAssignment(owner: fixture.reference("posts"), choice: .noTemplate))
        }
        let (workspace, library) = try fixture.reload(assignments)
        defer { workspace.deactivate() }
        #expect(library.loadError == nil)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let sourceBytes = try Data(contentsOf: fixture.source)

        for folder in [fixture.posts, fixture.alias] {
            #expect(throws: TemplateAssignmentError.self) { try workspace.templateAssignment(for: folder) }
            #expect(throws: TemplateAssignmentError.self) { try workspace.effectiveTemplateAssignment(for: folder) }
            #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(fixture.source, to: folder) }
            #expect(throws: TemplateAssignmentError.self) { try workspace.inheritTemplate(in: folder) }
            #expect(throws: TemplateAssignmentError.self) { try workspace.disableTemplate(in: folder) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
        #expect(try Data(contentsOf: fixture.source) == sourceBytes)
    }

    @Test func selectedAliasUsesCanonicalSavedOwnerWithoutAddingAnotherChoice() throws {
        let fixture = try TemplateOwnerFixture()
        let saved = FolderTemplateAssignment(owner: fixture.reference("posts"), choice: .noTemplate)
        let (workspace, library) = try fixture.reload([saved])
        defer { workspace.deactivate() }
        #expect(try workspace.templateAssignment(for: fixture.posts) == saved)
        #expect(try workspace.templateAssignment(for: fixture.alias) == saved)
        try workspace.assignTemplate(fixture.source, to: fixture.alias)
        let replacement = FolderTemplateAssignment(
            owner: fixture.reference("posts"), choice: .useSource(fixture.reference("base.md")))
        #expect(try workspace.templateAssignment(for: fixture.posts) == replacement)
        #expect(try workspace.templateAssignment(for: fixture.alias) == replacement)
        #expect(library.project(fixture.projectID)?.templateAssignments == [replacement])
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func ownerEscapingItsOwnRootIsRejectedEvenWhenTargetHasAnotherBinding() throws {
        let fixture = try TemplateOwnerFixture()
        let outside = try fixture.scratch.folder("outside")
        try FileManager.default.removeItem(at: fixture.alias)
        try FileManager.default.createSymbolicLink(at: fixture.alias, withDestinationURL: outside)
        try fixture.library.bindFolder(outside, to: fixture.projectID)
        let saved = FolderTemplateAssignment(owner: fixture.reference("alias"), choice: .noTemplate)
        let (workspace, library) = try fixture.reload([saved])
        defer { workspace.deactivate() }
        #expect(library.loadError == nil)
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        for folder in [fixture.posts, fixture.alias, outside] {
            #expect(throws: TemplateAssignmentError.self) { try workspace.templateAssignment(for: folder) }
            #expect(throws: TemplateAssignmentError.self) { try workspace.assignTemplate(fixture.source, to: folder) }
        }
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        #expect(try Data(contentsOf: fixture.source) == Data("unchanged source\r\n".utf8))
    }

    @Test func unresolvedAliasStaysInactiveAndIsNotCanonicalizedOrReactivated() throws {
        let fixture = try TemplateOwnerFixture()
        let unresolved = FolderTemplateAssignment(
            owner: fixture.reference("alias"), choice: .noTemplate, state: .unresolved)
        let active = FolderTemplateAssignment(owner: fixture.reference("posts"), choice: .noTemplate)
        let (workspace, library) = try fixture.reload([unresolved, active])
        defer { workspace.deactivate() }
        let bytes = try Data(contentsOf: library.storageURL)
        #expect(try workspace.templateAssignment(for: fixture.posts) == active)
        #expect(try workspace.templateAssignment(for: fixture.alias) == active)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        try workspace.assignTemplate(fixture.source, to: fixture.posts)
        let choices = try #require(library.project(fixture.projectID)?.templateAssignments)
        #expect(choices.count == 2)
        #expect(choices[0] == unresolved)
        #expect(choices[1].owner == fixture.reference("posts"))
        #expect(choices[1].state == .active)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func missingAndInaccessibleOwnersAndUnavailableRootsArePreservedWithoutBorrowingAccess() throws {
        let fixture = try TemplateOwnerFixture()
        let unavailable = FolderRoot(
            name: "Unavailable", bookmark: Data([0xFF]), lastKnownPath: fixture.posts.deletingLastPathComponent().path)
        try fixture.library.update(fixture.projectID) { $0.roots.append(unavailable) }
        let inaccessible = try fixture.scratch.folder("notes/private")
        let link = fixture.scratch.url.appending(path: "notes/private-alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: inaccessible)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inaccessible.path)
        defer {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessible.path)
            } catch {
                Issue.record(error)
            }
        }
        let preserved = [
            FolderTemplateAssignment(
                owner: FileReference(rootID: unavailable.id, relativePath: "alias"), choice: .noTemplate),
            FolderTemplateAssignment(owner: fixture.reference("missing"), choice: .noTemplate),
            FolderTemplateAssignment(owner: fixture.reference("private-alias"), choice: .noTemplate),
        ]
        let (workspace, library) = try fixture.reload(preserved)
        defer { workspace.deactivate() }
        #expect(library.loadError == nil)
        #expect(workspace.folders.first(where: { $0.id == unavailable.id })?.status == .needsAccess)
        let bytes = try Data(contentsOf: library.storageURL)
        #expect(try workspace.templateAssignment(for: fixture.posts) == nil)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        try workspace.assignTemplate(fixture.source, to: fixture.posts)
        let choices = try #require(library.project(fixture.projectID)?.templateAssignments)
        #expect(Array(choices.dropLast()) == preserved)
        #expect(choices.last?.owner == fixture.reference("posts"))
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func canonicalOwnersUnderDistinctRootIdentitiesRemainSeparateChoices() throws {
        let fixture = try TemplateOwnerFixture()
        let inner = try fixture.library.bindFolder(fixture.posts, to: fixture.projectID)
        let outerChoice = FolderTemplateAssignment(owner: fixture.reference("posts"), choice: .noTemplate)
        let innerChoice = FolderTemplateAssignment(
            owner: FileReference(rootID: inner.id, relativePath: ""), choice: .noTemplate)
        let (workspace, library) = try fixture.reload([outerChoice, innerChoice])
        defer { workspace.deactivate() }
        #expect(try workspace.templateAssignment(for: fixture.posts) == innerChoice)
        try workspace.assignTemplate(fixture.source, to: fixture.alias)
        let choices = try #require(library.project(fixture.projectID)?.templateAssignments)
        #expect(choices.count == 2)
        #expect(choices[0] == outerChoice)
        #expect(choices[1].owner == innerChoice.owner)
        #expect(choices[1].choice == .useSource(fixture.reference("base.md")))
    }
}

@MainActor private struct TemplateOwnerFixture {
    let scratch: Scratch
    let library: ProjectLibrary
    let projectID: UUID
    let rootID: UUID
    let posts: URL
    let alias: URL
    let source: URL

    init() throws {
        scratch = try Scratch()
        let root = try scratch.folder("notes")
        posts = try scratch.folder("notes/posts")
        alias = root.appending(path: "alias")
        source = try scratch.file("notes/base.md", "unchanged source\r\n")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: posts)
        library = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json")))
        projectID = try library.createProject(named: "Notes").id
        rootID = try library.bindFolder(root, to: projectID).id
    }

    func reference(_ path: String) -> FileReference {
        FileReference(rootID: rootID, relativePath: path)
    }

    func reload(_ assignments: [FolderTemplateAssignment]) throws -> (Workspace, ProjectLibrary) {
        try library.update(projectID) { $0.templateAssignments = assignments }
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let workspace = Workspace(projectID: projectID, library: relaunched)
        workspace.activate()
        return (workspace, relaunched)
    }
}
