import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct LifecycleSourceCoordinateTests {
    @Test(arguments: [false, true])
    func retainedOuterAndInnerSourceReferencesFollowTheVerifiedMove(destinationIsOuterRoot: Bool) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture(targetWithinOuter: destinationIsOuterRoot)
        let workspace = fixture.workspace
        let library = fixture.library
        defer { workspace.deactivate() }
        let independent = fixture.scratch.url.appending(path: "notes/hardlink.md")
        try FileManager.default.linkItem(at: fixture.source, to: independent)
        let independentOwner = try fixture.scratch.folder("notes/hardlink-owner")
        try workspace.assignTemplate(independent, to: independentOwner)
        let independentChoice = try workspace.templateAssignment(for: independentOwner)
        let result = workspace.move(fixture.source, into: fixture.target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil && result.legacyMovedURL == nil)
        let expected = FileReference(
            rootID: fixture.destinationRootID,
            relativePath: destinationIsOuterRoot ? "destination/source.md" : "source.md")
        #expect(try workspace.templateAssignment(for: fixture.outerOwner)?.choice == .useSource(expected))
        #expect(try workspace.templateAssignment(for: fixture.innerOwner)?.choice == .useSource(expected))
        #expect(try workspace.templateAssignment(for: independentOwner) == independentChoice)
        #expect(try String(contentsOf: independent, encoding: .utf8) == "original {title}")
        #expect(try String(contentsOf: moved, encoding: .utf8) == "original {title}")
        let plan = try workspace.prepareDocument(in: fixture.outerOwner, filenamePattern: "New")
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Coordinate")) else {
            Issue.record("Creation must read the saved source through its migrated coordinate")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "original Coordinate")
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test(arguments: [false, true])
    func restartUsesOnlyAffectedVerifiedCoordinates(completed: Bool) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let workspace = fixture.workspace
        let library = fixture.library
        let outer = try #require(workspace.project?.root(fixture.outerRootID))
        let unused = FolderRoot(name: "Unused alias", bookmark: outer.bookmark, lastKnownPath: outer.lastKnownPath)
        try library.update(workspace.projectID) {
            $0.roots.append(unused)
            $0.lastOpenedFile = FileReference(rootID: fixture.outerRootID, relativePath: "templates/source.md")
        }
        let before = workspace.project?.templateAssignments
        let (intent, _) = try fixture.captureMove(completed: completed)
        workspace.deactivate()
        let store = ProjectStore(fileURL: library.storageURL)
        try intent.write(to: store.fileURL, options: .atomic)
        var projects = try store.load()
        let index = try #require(projects[0].roots.firstIndex { $0.id == unused.id })
        projects[0].roots[index].bookmark = Data([0])
        try store.save(projects)
        let relaunched = ProjectLibrary(store: store)
        #expect(relaunched.loadError == nil)
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(!restarted.hasPendingLifecycleOperations && restarted.lastError == nil)
        if completed {
            let expected = FileReference(rootID: fixture.destinationRootID, relativePath: "source.md")
            #expect(restarted.project?.lastOpenedFile == expected)
            #expect(try restarted.templateAssignment(for: fixture.outerOwner)?.choice == .useSource(expected))
            #expect(try restarted.templateAssignment(for: fixture.innerOwner)?.choice == .useSource(expected))
        } else {
            #expect(restarted.project?.templateAssignments == before)
            #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "original {title}")
        }
        #expect(ProjectLibrary(store: store).projects == relaunched.projects)
    }

    @Test func mixedCoordinateDescendantsMigrateWithoutBorrowingAnotherProject() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["templates/group/source.md": "saved {title}"])
        defer { workspace.deactivate() }
        let group = scratch.url.appending(path: "notes/templates/group")
        let archive = try scratch.folder("notes/templates/group/archive")
        let owner = try scratch.folder("notes/owner")
        let source = group.appending(path: "source.md")
        try workspace.assignTemplate(source, to: owner)
        try workspace.disableTemplate(in: archive)
        let outerRootID = try #require(workspace.project?.roots.first?.id)
        let unresolved = FolderTemplateAssignment(
            owner: FileReference(rootID: outerRootID, relativePath: "templates/group/missing"),
            choice: .noTemplate, state: .unresolved)
        try library.update(workspace.projectID) { $0.templateAssignments.append(unresolved) }
        try library.bindFolder(group.deletingLastPathComponent(), to: workspace.projectID)
        try workspace.assignTemplate(source, to: group)
        let aliasOwner = try addSourceAlias(workspace: workspace, library: library, scratch: scratch)
        let target = try scratch.folder("destination/inner")
        try library.bindFolder(target.deletingLastPathComponent(), to: workspace.projectID)
        let destinationRoot = try library.bindFolder(target, to: workspace.projectID)
        let otherID = try library.createProject(named: "Other").id
        try library.bindFolder(scratch.url.appending(path: "notes"), to: otherID)
        let other = Workspace(projectID: otherID, library: library)
        other.activate()
        defer { other.deactivate() }
        try other.assignTemplate(source, to: owner)
        let otherBefore = library.project(otherID)
        let result = workspace.move(group, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error == nil)
        let expected = FileReference(rootID: destinationRoot.id, relativePath: "group/source.md")
        #expect(try workspace.templateAssignment(for: owner)?.choice == .useSource(expected))
        #expect(try workspace.templateAssignment(for: moved)?.choice == .useSource(expected))
        #expect(
            workspace.project?.templateAssignments.contains(
                FolderTemplateAssignment(
                    owner: aliasOwner, choice: .useSource(expected))) == true)
        #expect(try workspace.templateAssignment(for: moved.appending(path: "archive"))?.choice == .noTemplate)
        #expect(
            workspace.project?.templateAssignments.contains(
                FolderTemplateAssignment(
                    owner: FileReference(rootID: destinationRoot.id, relativePath: "group/missing"),
                    choice: .noTemplate, state: .unresolved)) == true)
        #expect(library.project(otherID) == otherBefore)
        #expect(try String(contentsOf: moved.appending(path: "source.md"), encoding: .utf8) == "saved {title}")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    private func addSourceAlias(workspace: Workspace, library: ProjectLibrary, scratch: Scratch) throws -> FileReference
    {
        let original = try #require(workspace.project?.roots.first)
        let alias = FolderRoot(
            name: "Equivalent root", bookmark: original.bookmark, lastKnownPath: original.lastKnownPath)
        try scratch.folder("notes/alias-owner")
        let owner = FileReference(rootID: alias.id, relativePath: "alias-owner")
        try library.update(workspace.projectID) {
            $0.roots.append(alias)
            $0.templateAssignments.append(
                FolderTemplateAssignment(
                    owner: owner,
                    choice: .useSource(FileReference(rootID: alias.id, relativePath: "templates/group/source.md"))))
        }
        return owner
    }
}

@MainActor struct LifecycleSourceCoordinateFixture {
    let scratch: Scratch
    let workspace: Workspace
    let library: ProjectLibrary
    let source: URL
    let outerOwner: URL
    let innerOwner: URL
    let target: URL
    let outerRootID: UUID
    let innerRootID: UUID
    let destinationRootID: UUID

    init(targetWithinOuter: Bool = false) async throws {
        scratch = try Scratch()
        (workspace, library) = try await scratch.workspace(files: ["templates/source.md": "original {title}"])
        source = scratch.url.appending(path: "notes/templates/source.md")
        outerOwner = try scratch.folder("notes/owner")
        innerOwner = try scratch.folder("notes/templates/owner")
        target = try scratch.folder(targetWithinOuter ? "notes/destination" : "destination")
        outerRootID = try #require(workspace.project?.roots.first?.id)
        try workspace.assignTemplate(source, to: outerOwner)
        innerRootID = try library.bindFolder(source.deletingLastPathComponent(), to: workspace.projectID).id
        try workspace.assignTemplate(source, to: innerOwner)
        destinationRootID = targetWithinOuter ? outerRootID : try library.bindFolder(target, to: workspace.projectID).id
    }

    func captureMove(completed: Bool) throws -> (Data, LifecycleResult) {
        var intent = Data()
        workspace.lifecycleOperations.move = { url, destination in
            intent = try Data(contentsOf: library.storageURL)
            if completed { return try FileOperations.move(url, into: destination) }
            throw CocoaError(.userCancelled)
        }
        let result = workspace.move(source, into: target)
        #expect(!intent.isEmpty)
        return (intent, result)
    }
}
