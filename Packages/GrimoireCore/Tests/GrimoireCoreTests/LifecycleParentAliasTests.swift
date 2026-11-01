import Foundation
import Testing

@testable import GrimoireCore

private enum AliasSaveAttempt: CaseIterable, Sendable { case manual, autosave, keepMine }

private struct AliasSaveCase: Sendable {
    let foreign: Bool
    let subtree: Bool
    let resolved: Bool
    let attempt: AliasSaveAttempt

    static let all = [false, true].flatMap { foreign in
        [false, true].flatMap { subtree in
            [false, true].flatMap { resolved in
                AliasSaveAttempt.allCases.map {
                    Self(foreign: foreign, subtree: subtree, resolved: resolved, attempt: $0)
                }
            }
        }
    }
}

@MainActor @Suite(.mainActorGate) struct LifecycleParentAliasTests {
    @Test(arguments: [false, true], AliasSaveCase.all)
    private func parentAliasCannotHidePendingSave(rename: Bool, scenario: AliasSaveCase) async throws {
        let fixture = try await ParentAliasFixture(rename: rename, foreign: scenario.foreign, subtree: scenario.subtree)
        defer { fixture.cleanup() }
        let document = fixture.document
        if scenario.resolved { document.moved(to: fixture.actualURL) }
        document.text = "dirty through alias"
        if scenario.attempt == .keepMine {
            // This external writer changes bytes without replacing the identity recovery still needs.
            try Data("external".utf8).write(to: fixture.actualURL)
            document.checkDisk()
            #expect(!document.keepMine())
            #expect(document.conflict == "external")
        } else if scenario.attempt == .autosave {
            document.autosaveDelay = .milliseconds(1)
            document.text = "autosave through alias"
            try await until { document.saveError != nil }
        } else {
            #expect(!document.save())
        }
        #expect(!document.close())
        try fixture.assertBlocked(disk: scenario.attempt == .keepMine ? "external" : "original")
        try fixture.restoreSettingsAccess()
        fixture.workspace.reconcileLifecycleOperations()
        #expect(fixture.workspace.hasPendingLifecycleOperations)
        #expect(fixture.workspace.lastError != nil)
        try fixture.assertBlocked(disk: scenario.attempt == .keepMine ? "external" : "original")
        try fixture.saveUnrelatedDocument()
        try fixture.repairParent()
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        if scenario.attempt == .keepMine { #expect(document.keepMine()) } else { #expect(document.save()) }
        #expect(try String(contentsOf: document.url, encoding: .utf8) == document.text)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(restarted.project(fixture.workspace.projectID)?.pendingLifecycleOperations.isEmpty == true)
        if scenario.foreign {
            #expect(restarted.project(fixture.requester.projectID)?.templateAssignments.isEmpty == true)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func parentAliasStillReservesConfigurationAndSourceReads(rename: Bool, subtree: Bool) async throws {
        let fixture = try await ParentAliasFixture(rename: rename, foreign: false, subtree: subtree)
        defer { fixture.cleanup() }
        let owner = try fixture.scratch.folder("notes/new-owner")
        for source in [fixture.lexicalURL, fixture.actualURL] {
            #expect(throws: (any Error).self) { try fixture.workspace.assignTemplate(source, to: owner) }
            let reference = try #require(fixture.workspace.reference(for: source))
            let ownerReference = try #require(fixture.workspace.reference(for: owner))
            #expect(throws: (any Error).self) {
                try fixture.library.update(fixture.workspace.projectID) {
                    $0.templateAssignments.append(
                        FolderTemplateAssignment(owner: ownerReference, choice: .useSource(reference)))
                }
            }
        }
        let fresh = try fixture.workspace.prepareDocument(in: fixture.dependentOwner, filenamePattern: "Fresh")
        for (plan, name) in [(fixture.stalePlan, "Stale"), (fresh, "Fresh")] {
            guard case .sourceFailure(_, let error) = fixture.workspace.createDocument(plan, naming: .edited(name))
            else {
                Issue.record("An alias must not bypass pending-dependent source reads"); return
            }
            #expect(error is LifecycleError)
        }
        if subtree {
            #expect(throws: (any Error).self) {
                try fixture.workspace.prepareDocument(
                    in: fixture.actualURL.deletingLastPathComponent(), filenamePattern: "Child")
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.dependentOwner.path).isEmpty)
        #expect(try Data(contentsOf: fixture.library.storageURL) == fixture.settingsBytes)
        #expect(try LifecycleIdentity(fixture.actualURL) == fixture.identity)
    }

    @Test(arguments: [false, true], [false, true])
    func reservationPathsSurviveAnAliasPointingAtAnUnrelatedItem(rename: Bool, foreign: Bool) async throws {
        let fixture = try await ParentAliasFixture(rename: rename, foreign: foreign)
        defer { fixture.cleanup() }
        let replacement = try fixture.scratch.folder("notes/replacement")
        let file = try fixture.scratch.file("notes/replacement/" + fixture.lexicalURL.lastPathComponent, "unrelated")
        try FileManager.default.removeItem(at: fixture.target)
        try FileManager.default.createSymbolicLink(at: fixture.target, withDestinationURL: replacement)
        #expect(try LifecycleIdentity(file) != fixture.identity)
        for url in [fixture.lexicalURL, file] {
            let document = try OpenDocument(
                url: url, autosaveDelay: .seconds(3600),
                authorizeWrite: { try fixture.requester.authorizeDocumentSave(at: $0) })
            document.text = "must not replace"
            #expect(!document.save() && !document.close())
            #expect(document.isDirty && document.savedText == "unrelated")
            document.discard()
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "unrelated")
        #expect(try LifecycleIdentity(fixture.actualURL) == fixture.identity)
        #expect(try Data(contentsOf: fixture.library.storageURL) == fixture.settingsBytes)
        #expect(fixture.workspace.hasPendingLifecycleOperations)
    }

    @Test(arguments: [false, true], [false, true])
    func recordedPhysicalIdentityAlsoReservesHardlinks(rename: Bool, foreign: Bool) async throws {
        let fixture = try await ParentAliasFixture(rename: rename, foreign: foreign)
        defer { fixture.cleanup() }
        let link = fixture.scratch.url.appending(path: "notes/hardlink.md")
        try FileManager.default.linkItem(at: fixture.actualURL, to: link)
        let document = try OpenDocument(
            url: link, autosaveDelay: .seconds(3600),
            authorizeWrite: { try fixture.requester.authorizeDocumentSave(at: $0) })
        defer { document.discard() }
        document.text = "hardlink buffer"
        #expect(!document.save() && !document.close())
        #expect(document.isDirty && document.savedText == "original")
        #expect(try LifecycleIdentity(link) == fixture.identity)
        #expect(try String(contentsOf: link, encoding: .utf8) == "original")
        let owner = try fixture.scratch.folder("notes/hardlink-owner")
        #expect(throws: (any Error).self) { try fixture.workspace.assignTemplate(link, to: owner) }
        try fixture.repairParent()
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        #expect(document.save())
    }
}

@MainActor private struct ParentAliasFixture {
    let scratch: Scratch
    let library: ProjectLibrary
    let workspace: Workspace
    let requester: Workspace
    let document: OpenDocument
    let identity: LifecycleIdentity
    let target: URL
    let relocated: URL
    let lexicalURL: URL
    let actualURL: URL
    let dependentOwner: URL
    let stalePlan: DocumentCreationPlan
    let settingsBytes: Data

    init(rename: Bool, foreign: Bool, subtree: Bool = false) async throws {
        scratch = try Scratch()
        let movingPath = subtree ? "origin" : "source.md"
        let relative = subtree ? "child/source.md" : ""
        let sourcePath = (rename ? "target/" : "") + movingPath
        let filePath = sourcePath + (subtree ? "/" + relative : "")
        (workspace, library) = try await scratch.workspace(files: [filePath: "original"])
        let root = scratch.url.appending(path: "notes")
        target = try scratch.folder("notes/target")
        relocated = root.appending(path: "relocated")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(root.appending(path: filePath), to: owner)
        requester = try Self.makeRequester(workspace: workspace, library: library, root: root, foreign: foreign)
        let leaf = rename ? (subtree ? "renamed" : "renamed.md") : movingPath
        let aliasPath = "relocated/" + leaf + (subtree ? "/" + relative : "")
        dependentOwner = try scratch.folder("notes/dependent")
        let rootID = try #require(workspace.project?.roots.first?.id)
        try library.update(workspace.projectID) {
            $0.templateAssignments.append(
                FolderTemplateAssignment(
                    owner: FileReference(rootID: rootID, relativePath: "dependent"),
                    choice: .useSource(FileReference(rootID: rootID, relativePath: aliasPath))))
        }
        stalePlan = try workspace.prepareDocument(in: dependentOwner, filenamePattern: "Stale")
        Self.failFinalPersistence(in: workspace, directory: library.storageURL.deletingLastPathComponent())
        let source = root.appending(path: sourcePath)
        let result = rename ? workspace.rename(source, to: "renamed") : workspace.move(source, into: target)
        let moved = try #require(result.movedURL)
        #expect(result.error != nil)
        lexicalURL = subtree ? moved.appending(path: relative) : moved
        let context = requester
        document = try OpenDocument(
            url: lexicalURL, autosaveDelay: .seconds(3600),
            authorizeWrite: { try context.authorizeDocumentSave(at: $0) })
        document.versions = VersionStore(folder: root.appending(path: "history"))
        identity = try LifecycleIdentity(lexicalURL)
        try FileManager.default.moveItem(at: target, to: relocated)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: relocated)
        actualURL = lexicalURL.resolvingSymlinksInPath()
        settingsBytes = try Data(contentsOf: library.storageURL)
    }

    private static func makeRequester(workspace: Workspace, library: ProjectLibrary, root: URL, foreign: Bool) throws
        -> Workspace
    {
        var id = workspace.projectID
        if foreign {
            id = try library.createProject(named: "Requester").id
            try library.bindFolder(root, to: id)
        }
        let requester = Workspace(projectID: id, library: library)
        requester.activate()
        return requester
    }

    private static func failFinalPersistence(in workspace: Workspace, directory: URL) {
        workspace.lifecycleOperations.rename = { url, name in
            let moved = try FileOperations.rename(url, to: name)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
    }

    func assertBlocked(disk: String) throws {
        #expect(document.isDirty && document.savedText == "original")
        #expect(document.saveError != nil)
        #expect(document.versions?.versions(of: document.url).isEmpty == true)
        #expect(try LifecycleIdentity(document.url) == identity)
        #expect(try String(contentsOf: document.url, encoding: .utf8) == disk)
        #expect(try Data(contentsOf: library.storageURL) == settingsBytes)
    }

    func saveUnrelatedDocument() throws {
        let file = try scratch.file("notes/unrelated.md", "independent")
        let other = try OpenDocument(url: file, authorizeWrite: { try requester.authorizeDocumentSave(at: $0) })
        other.text = "unrelated save"
        #expect(other.close())
        #expect(workspace.hasPendingLifecycleOperations)
    }

    func restoreSettingsAccess() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: library.storageURL.deletingLastPathComponent().path)
    }

    func repairParent() throws {
        try FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: relocated, to: target)
        try restoreSettingsAccess()
        document.moved(to: lexicalURL)
    }

    func cleanup() {
        try? restoreSettingsAccess()
        document.discard()
        requester.deactivate()
        workspace.deactivate()
    }
}
