import Foundation
import Testing

@testable import GrimoireCore

private enum PendingSaveAttempt: CaseIterable, Sendable { case manual, autosave, keepMine }

@MainActor @Suite struct LifecycleSaveTests {
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

    init(rename: Bool, subtree: Bool = false) async throws {
        scratch = try Scratch()
        (workspace, library) = try await scratch.workspace(files: ["group/source.md": "original"])
        let source = scratch.url.appending(path: "notes/group/source.md")
        let owner = try scratch.folder("notes/owner")
        let target = try scratch.folder("notes/target")
        try workspace.assignTemplate(source, to: owner)
        otherWorkspace = Workspace(projectID: workspace.projectID, library: library)
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
