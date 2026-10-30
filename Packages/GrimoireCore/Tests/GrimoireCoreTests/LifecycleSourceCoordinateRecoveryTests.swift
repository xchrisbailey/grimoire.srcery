import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct LifecycleSourceCoordinateRecoveryTests {
    @Test(arguments: [
        "missing", "null", "empty", "wrong type", "duplicate", "unknown root", "primary root", "invalid identity",
        "broader prefix", "traversal",
    ])
    func malformedProjectionPreservesTheOriginalStoreAndFiles(scenario: String) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let (intent, _) = try fixture.captureMove(completed: false)
        fixture.workspace.deactivate()
        let bytes = try malformedSnapshot(scenario, intent: intent, fixture: fixture)
        try bytes.write(to: fixture.library.storageURL, options: .atomic)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        #expect(restarted.loadError != nil)
        #expect(throws: (any Error).self) { try restarted.createProject(named: "Must not overwrite") }
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        #expect(try String(contentsOf: fixture.source, encoding: .utf8) == "original {title}")
        #expect(!FileManager.default.fileExists(atPath: fixture.target.appending(path: "source.md").path))
    }

    @Test(arguments: ["unavailable projection root", "substituted projection parent"])
    func restartRetainsRepairWhenAlternativeCoordinatesCannotBeVerified(scenario: String) async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let (intent, result) = try fixture.captureMove(completed: true)
        let moved = try #require(result.movedURL)
        let before = try #require(fixture.workspace.project).templateAssignments
        fixture.workspace.deactivate()
        let store = ProjectStore(fileURL: fixture.library.storageURL)
        try intent.write(to: store.fileURL, options: .atomic)
        var projects = try store.load()
        let originalChoices = projects[0].templateAssignments
        let index = try #require(projects[0].roots.firstIndex { $0.id == fixture.outerRootID })
        if scenario == "unavailable projection root" {
            projects[0].roots[index].bookmark = Data([0])
        } else {
            let original = fixture.source.deletingLastPathComponent()
            let retained = fixture.scratch.url.appending(path: "retained-templates")
            try FileManager.default.moveItem(at: original, to: retained)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: retained)
            let primary = try #require(projects[0].roots.firstIndex { $0.id == fixture.innerRootID })
            projects[0].roots[primary].bookmark = try FolderBookmark.make(for: retained)
        }
        try store.save(projects)
        let bytes = try Data(contentsOf: store.fileURL)
        let relaunched = ProjectLibrary(store: store)
        #expect(relaunched.loadError == nil)
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: relaunched)
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations && restarted.lastError != nil)
        #expect(restarted.project?.templateAssignments == originalChoices)
        #expect(restarted.project?.templateAssignments != before)
        #expect(throws: (any Error).self) { try restarted.authorizeDocumentSave(at: moved) }
        restarted.reconcileLifecycleOperations()
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(try Data(contentsOf: store.fileURL) == bytes)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "original {title}")
    }

    @Test func failedFinalSaveKeepsEveryCoordinateAndItsAssignmentsReserved() async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        let directory = fixture.library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let before = workspace.project?.templateAssignments
        workspace.lifecycleOperations.move = { url, target in
            let moved = try FileOperations.move(url, into: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = workspace.move(fixture.source, into: fixture.target)
        let moved = try #require(result.movedURL)
        #expect(result.error != nil && workspace.hasPendingLifecycleOperations)
        #expect(workspace.project?.templateAssignments == before)
        #expect(throws: (any Error).self) { try workspace.authorizeDocumentSave(at: moved) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let savedIntent = try Data(contentsOf: fixture.library.storageURL)
        #expect(throws: (any Error).self) { try workspace.inheritTemplate(in: fixture.outerOwner) }
        #expect(throws: (any Error).self) { try workspace.disableTemplate(in: fixture.innerOwner) }
        #expect(throws: (any Error).self) {
            try fixture.library.replaceBookmark(
                of: fixture.outerRootID, in: workspace.projectID, with: fixture.scratch.folder("replacement"))
        }
        #expect(workspace.rename(fixture.outerOwner, to: "changed").movedURL == nil)
        #expect(try Data(contentsOf: fixture.library.storageURL) == savedIntent)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations && workspace.lastError == nil)
        let expected = FileReference(rootID: fixture.destinationRootID, relativePath: "source.md")
        #expect(try workspace.templateAssignment(for: fixture.outerOwner)?.choice == .useSource(expected))
        #expect(try workspace.templateAssignment(for: fixture.innerOwner)?.choice == .useSource(expected))
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL)).projects
                == fixture.library.projects)
    }

    @Test func foreignDirtyEditorCannotRetireProjectedIntentByReplacingTheMovedFile() async throws {
        let fixture = try await LifecycleSourceCoordinateFixture()
        defer { fixture.workspace.deactivate() }
        let otherID = try fixture.library.createProject(named: "Other").id
        try fixture.library.bindFolder(fixture.scratch.url.appending(path: "notes"), to: otherID)
        try fixture.library.bindFolder(fixture.target, to: otherID)
        let other = Workspace(projectID: otherID, library: fixture.library)
        other.activate()
        defer { other.deactivate() }
        let document = try OpenDocument(
            url: fixture.source, autosaveDelay: .seconds(3600),
            authorizeWrite: { try other.authorizeDocumentSave(at: $0) })
        defer { document.discard() }
        document.text = "foreign dirty buffer"
        let directory = fixture.library.storageURL.deletingLastPathComponent()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        fixture.workspace.lifecycleOperations.move = { url, target in
            let moved = try FileOperations.move(url, into: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        let result = fixture.workspace.move(fixture.source, into: fixture.target)
        let moved = try #require(result.movedURL)
        let identity = try LifecycleIdentity(moved)
        document.moved(to: moved)
        #expect(!document.save() && !document.close())
        #expect(document.isDirty && document.text == "foreign dirty buffer" && document.savedText == "original {title}")
        #expect(try LifecycleIdentity(moved) == identity)
        #expect(try String(contentsOf: moved, encoding: .utf8) == "original {title}")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(!document.save())
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        #expect(document.save())
        #expect(try String(contentsOf: moved, encoding: .utf8) == "foreign dirty buffer")
        #expect(other.project?.templateAssignments.isEmpty == true)
    }

    private func malformedSnapshot(
        _ scenario: String, intent: Data, fixture: LifecycleSourceCoordinateFixture
    ) throws -> Data {
        let original = try #require(String(data: intent, encoding: .utf8))
        let range = try #require(
            original.range(of: "\"sourceProjections\"\\s*:\\s*\\[[\\s\\S]*?\\]", options: .regularExpression))
        let fragment = String(original[range])
        let replacement: String
        switch scenario {
        case "missing": replacement = fragment.replacingOccurrences(of: "sourceProjections", with: "unknownProjections")
        case "null": replacement = "\"sourceProjections\" : null"
        case "empty": replacement = "\"sourceProjections\" : []"
        case "wrong type": replacement = "\"sourceProjections\" : 0"
        case "duplicate":
            let start = try #require(fragment.firstIndex(of: "["))
            let end = try #require(fragment.lastIndex(of: "]"))
            let body = fragment[fragment.index(after: start)..<end]
            replacement = "\"sourceProjections\" : [" + body + "," + body + "]"
        case "unknown root", "primary root":
            let id = scenario == "primary root" ? fixture.innerRootID : UUID()
            replacement = fragment.replacingOccurrences(of: fixture.outerRootID.uuidString, with: id.uuidString)
        case "invalid identity":
            replacement = fragment.replacingOccurrences(of: "\"type\" : 16384", with: "\"type\" : 0")
        default:
            replacement = fragment.replacingOccurrences(
                of: "templates\\/source.md", with: scenario == "traversal" ? "../source.md" : "templates")
        }
        let changed = original.replacingCharacters(in: range, with: replacement)
        try #require(changed != original)
        return Data(changed.utf8)
    }
}
