import Foundation
import Testing

@testable import GrimoireCore

private enum PendingSaveAttempt: CaseIterable, Sendable { case manual, autosave, keepMine }

@MainActor @Suite struct LifecycleSaveTests {
    @Test(arguments: [false, true])
    func crossRootPendingSubtreeProtectsDirtyEditorsInBothProjects(separateProject: Bool) async throws {
        let fixture = try await PendingSaveFixture(
            rename: false, subtree: true, separateProject: separateProject, crossRoot: true)
        defer { fixture.cleanup() }
        #expect(!fixture.document.save())
        #expect(!fixture.otherDocument.save())
        #expect(!fixture.document.close())
        #expect(!fixture.otherDocument.close())
        try fixture.assertBlocked()
        #expect(fixture.otherDocument.isDirty && fixture.otherDocument.savedText == "original")
        #expect(fixture.otherDocument.text == "other buffer")
        try fixture.restoreSettingsAccess()
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        #expect(fixture.document.save())
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == "dirty buffer")
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL)).projects
                == fixture.library.projects)
    }

    @Test func removedProjectDoesNotAuthorizeAnOrphanDocument() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["page.md": "original"])
        defer { workspace.deactivate() }
        let file = scratch.url.appending(path: "notes/page.md")
        let document = try OpenDocument(
            url: file, autosaveDelay: .seconds(3600),
            authorizeWrite: { try workspace.authorizeDocumentSave(at: $0) })
        defer { document.discard() }
        #expect(document.save())
        try library.deleteProject(workspace.projectID)
        let identity = try LifecycleIdentity(file)
        document.text = "orphan buffer"
        #expect(!document.save() && !document.close())
        #expect(document.isDirty && document.savedText == "original")
        #expect(try LifecycleIdentity(file) == identity)
        #expect(try String(contentsOf: file, encoding: .utf8) == "original")
    }

    @Test(arguments: [false, true], PendingSaveAttempt.allCases)
    private func anotherProjectCannotReplacePendingPhysicalIdentity(rename: Bool, attempt: PendingSaveAttempt)
        async throws
    {
        let fixture = try await PendingSaveFixture(rename: rename, separateProject: true)
        defer { fixture.cleanup() }
        let requester = try OpenDocument(
            url: fixture.moved, autosaveDelay: .seconds(3600),
            authorizeWrite: { try fixture.otherWorkspace.authorizeDocumentSave(at: $0) })
        defer { requester.discard() }
        requester.versions = VersionStore(folder: fixture.scratch.url.appending(path: "requester-versions"))
        requester.text = "project B buffer"
        if attempt == .keepMine {
            try Data("external".utf8).write(to: fixture.moved)
            requester.checkDisk()
            #expect(!requester.keepMine())
            #expect(requester.conflict == "external")
        } else if attempt == .autosave {
            requester.autosaveDelay = .milliseconds(1)
            requester.text = "project B autosave buffer"
            try await until { requester.saveError != nil }
        } else {
            #expect(!requester.save())
        }
        #expect(!requester.close())
        #expect(requester.saveError != nil)
        #expect(requester.isDirty && requester.savedText == "original")
        #expect(requester.versions?.versions(of: fixture.moved).isEmpty == true)
        #expect(try LifecycleIdentity(fixture.moved) == fixture.identity)
        #expect(
            try String(contentsOf: fixture.moved, encoding: .utf8) == (attempt == .keepMine ? "external" : "original"))
        let independent = try fixture.scratch.file("notes/independent.md", "unchanged")
        let unrelated = try OpenDocument(
            url: independent,
            authorizeWrite: { try fixture.otherWorkspace.authorizeDocumentSave(at: $0) })
        unrelated.text = "independent buffer"
        #expect(unrelated.close())
        fixture.workspace.deactivate()
        #expect(throws: (any Error).self) { try fixture.otherWorkspace.authorizeDocumentSave(at: fixture.moved) }
        fixture.workspace.activate()
        try fixture.restoreSettingsAccess()
        #expect(throws: (any Error).self) { try fixture.otherWorkspace.authorizeDocumentSave(at: fixture.moved) }
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        if attempt == .keepMine { #expect(requester.keepMine()) } else { #expect(requester.save()) }
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == requester.text)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(restarted.project(fixture.workspace.projectID)?.pendingLifecycleOperations.isEmpty == true)
        #expect(restarted.project(fixture.otherWorkspace.projectID)?.templateAssignments.isEmpty == true)
    }

    @Test func foreignReservationsGuardAliasesEvenWhenOwnerBookmarkCannotResolve() async throws {
        let fixture = try await PendingSaveFixture(rename: true, separateProject: true)
        defer { fixture.cleanup() }
        try fixture.restoreSettingsAccess()
        var projects = fixture.library.projects
        let owner = try #require(projects.firstIndex { $0.id == fixture.workspace.projectID })
        projects[owner].roots[0].bookmark = Data()
        let store = ProjectStore(fileURL: fixture.scratch.url.appending(path: "unavailable-owner.json"))
        try store.save(projects)
        let reloaded = ProjectLibrary(store: store)
        let requester = Workspace(projectID: fixture.otherWorkspace.projectID, library: reloaded)
        requester.activate()
        defer { requester.deactivate() }
        #expect(throws: (any Error).self) { try requester.authorizeDocumentSave(at: fixture.moved) }
        let alias = fixture.moved.deletingLastPathComponent().appending(
            path: fixture.moved.lastPathComponent.uppercased())
        let sensitive = try fixture.moved.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames
        if sensitive == true {
            try requester.authorizeDocumentSave(at: alias)
        } else {
            #expect(throws: (any Error).self) { try requester.authorizeDocumentSave(at: alias) }
        }
        let independent = try fixture.scratch.file("notes/independent.md", "independent")
        try requester.authorizeDocumentSave(at: independent)
        #expect(try LifecycleIdentity(fixture.moved) == fixture.identity)
        #expect(reloaded.project(fixture.workspace.projectID)?.pendingLifecycleOperations.count == 1)
    }

    @Test(arguments: [false, true])
    func blockedSaveRetainsOriginalUntilConfigurationCanFinish(rename: Bool) async throws {
        let fixture = try await PendingSaveFixture(rename: rename)
        defer { fixture.cleanup() }
        let document = fixture.document
        #expect(!document.save())
        #expect(!document.close())
        try fixture.assertBlocked()
        try fixture.restoreSettingsAccess()
        #expect(document.save())
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        #expect(document.close())
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == "dirty buffer")
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(restarted.project(fixture.workspace.projectID)?.pendingLifecycleOperations.isEmpty == true)
        #expect(
            restarted.project(fixture.workspace.projectID)?.templateAssignments
                == fixture.workspace.project?.templateAssignments)
    }

    @Test(
        arguments: [false, true],
        [false, true].flatMap { subtree in
            PendingSaveAttempt.allCases.map { (subtree, $0) }
        })
    private func everyWindowAndWritePathProtectsPendingIdentity(
        rename: Bool,
        scenario: (Bool, PendingSaveAttempt)
    ) async throws {
        let (subtree, attempt) = scenario
        let fixture = try await PendingSaveFixture(rename: rename, subtree: subtree)
        defer { fixture.cleanup() }
        let other = fixture.otherDocument
        if attempt == .keepMine {
            // An external non-atomic editor can change bytes without replacing recovery's inode.
            try Data("external edit".utf8).write(to: fixture.moved)
            fixture.document.checkDisk()
            other.checkDisk()
            #expect(!fixture.document.keepMine())
            #expect(!other.keepMine())
            #expect(fixture.document.conflict == "external edit")
            #expect(other.conflict == "external edit")
        } else if attempt == .autosave {
            fixture.document.autosaveDelay = .milliseconds(1)
            other.autosaveDelay = .milliseconds(1)
            fixture.document.text = "autosave buffer"
            other.text = "other autosave buffer"
            try await until { fixture.document.saveError != nil && other.saveError != nil }
        } else {
            #expect(!fixture.document.save())
            #expect(!other.save())
        }
        try fixture.assertBlocked(expectedDisk: attempt == .keepMine ? "external edit" : "original")
        #expect(other.saveError != nil)
        #expect(other.isDirty)
        #expect(other.savedText == "original")
        #expect(!other.close())
        let unrelated = try fixture.scratch.file("notes/unrelated.md", "unchanged")
        let independent = try OpenDocument(
            url: unrelated,
            authorizeWrite: { try fixture.otherWorkspace.authorizeDocumentSave(at: $0) })
        independent.text = "unrelated save"
        #expect(independent.close())
        #expect(fixture.workspace.hasPendingLifecycleOperations)
        try fixture.restoreSettingsAccess()
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        if attempt == .keepMine { #expect(fixture.document.keepMine()) } else { #expect(fixture.document.save()) }
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == fixture.document.text)
        #expect(other.savedText == "original")
        other.checkDisk()
        #expect(other.keepMine())
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == other.text)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(restarted.project(fixture.workspace.projectID)?.pendingLifecycleOperations.isEmpty == true)
    }
}

@MainActor private struct PendingSaveFixture {
    let scratch: Scratch
    let workspace: Workspace
    let otherWorkspace: Workspace
    let library: ProjectLibrary
    let document: OpenDocument
    let otherDocument: OpenDocument
    let moved: URL
    let identity: LifecycleIdentity
    let directory: URL

    init(rename: Bool, subtree: Bool = false, separateProject: Bool = false, crossRoot: Bool = false) async throws {
        scratch = try Scratch()
        (workspace, library) = try await scratch.workspace(files: ["group/source.md": "original"])
        let source = scratch.url.appending(path: "notes/group/source.md")
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder(crossRoot ? "destination" : "notes/target")
        if crossRoot { try library.bindFolder(target, to: workspace.projectID) }
        try workspace.assignTemplate(source, to: owner)
        let otherID: Project.ID
        if separateProject {
            otherID = try library.createProject(named: "Other project").id
            try library.bindFolder(source.deletingLastPathComponent().deletingLastPathComponent(), to: otherID)
            if crossRoot { try library.bindFolder(target, to: otherID) }
        } else {
            otherID = workspace.projectID
        }
        otherWorkspace = Workspace(projectID: otherID, library: library)
        otherWorkspace.activate()
        let context = workspace
        let otherContext = otherWorkspace
        document = try OpenDocument(
            url: source, autosaveDelay: .seconds(3600),
            authorizeWrite: { try context.authorizeDocumentSave(at: $0) })
        otherDocument = try OpenDocument(
            url: source, autosaveDelay: .seconds(3600),
            authorizeWrite: { try otherContext.authorizeDocumentSave(at: $0) })
        document.versions = VersionStore(folder: scratch.url.appending(path: "versions"))
        document.text = "dirty buffer"
        otherDocument.text = "other buffer"
        directory = library.storageURL.deletingLastPathComponent()
        let settingsDirectory = directory
        workspace.lifecycleOperations.rename = { url, name in
            let moved = try FileOperations.rename(url, to: name)
            try Self.denySettingsAccess(settingsDirectory)
            return moved
        }
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try Self.denySettingsAccess(settingsDirectory)
            return moved
        }
        let moving = subtree ? source.deletingLastPathComponent() : source
        let result = rename ? workspace.rename(moving, to: "renamed") : workspace.move(moving, into: target)
        let destination = try #require(result.movedURL)
        #expect(result.error != nil)
        moved = subtree ? destination.appending(path: "source.md") : destination
        document.moved(to: moved)
        otherDocument.moved(to: moved)
        identity = try LifecycleIdentity(moved)
    }

    private static func denySettingsAccess(_ directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    }

    func assertBlocked(expectedDisk: String = "original") throws {
        #expect(document.saveError != nil)
        #expect(document.isDirty)
        #expect(document.savedText == "original")
        #expect(document.versions?.versions(of: moved).isEmpty == true)
        #expect(try LifecycleIdentity(moved) == identity)
        #expect(try String(contentsOf: moved, encoding: .utf8) == expectedDisk)
        #expect(workspace.hasPendingLifecycleOperations)
    }

    func restoreSettingsAccess() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    func cleanup() {
        try? restoreSettingsAccess()
        document.discard()
        otherDocument.discard()
        workspace.deactivate()
        otherWorkspace.deactivate()
    }
}
