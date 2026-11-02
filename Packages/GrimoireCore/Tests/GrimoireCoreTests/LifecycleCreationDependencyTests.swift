import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite(.mainActorGate) struct LifecycleCreationDependencyTests {
    @Test(arguments: [false, true], [false, true])
    func pendingSourceBlocksFreshAndStalePlansBeforeReadingReplacement(stale: Bool, invalidBytes: Bool) async throws {
        let replacement = invalidBytes ? Data([0xff, 0]) : Data("unrelated replacement {title}".utf8)
        let fixture = try await PendingCreationFixture(replacement: replacement)
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        let plan =
            stale ? fixture.stalePlan : try workspace.prepareDocument(in: fixture.destination, filenamePattern: "New")
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        requireSourceBlocked(workspace.createDocument(plan, naming: .edited("Blocked")))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
        #expect(fixture.library.projects == before)
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        #expect(try Data(contentsOf: fixture.source) == replacement)
        #expect(try String(contentsOf: fixture.movedSource, encoding: .utf8) == "original {title}")
        try assertIndependentCreation(fixture, plan: plan)
        let later = try workspace.prepareDocument(in: fixture.destination, filenamePattern: "Later")
        requireSourceBlocked(workspace.createDocument(later, naming: .edited("Still blocked")))
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(fixture.library.projects == before)
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        #expect(try Data(contentsOf: fixture.source) == replacement)
    }

    @Test func pendingSourceIntroducedDuringWritingBlocksPublication() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original {title}"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/source.md")
        let owner = try scratch.folder("notes/owner")
        let holding = try scratch.folder("notes/holding")
        try workspace.assignTemplate(source, to: owner)
        let plan = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        let directory = library.storageURL.deletingLastPathComponent()
        workspace.lifecycleOperations.move = { url, folder in
            let moved = try FileOperations.move(url, into: folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return moved
        }
        var operations = DocumentCreationOperations()
        operations.write = { _ in
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
            let result = workspace.move(source, into: holding)
            #expect(result.movedURL != nil)
            #expect(workspace.hasPendingLifecycleOperations)
            try Data("unrelated replacement".utf8).write(to: source)
        }
        let result = workspace.createDocument(
            plan, naming: .edited("Blocked"), now: .now, calendar: .current,
            operations: operations)
        guard case .failed(let error) = result else {
            Issue.record("A new pending dependency must block publication")
            return
        }
        #expect(error is LifecycleError)
        #expect(try FileManager.default.contentsOfDirectory(atPath: owner.path).isEmpty)
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: source, encoding: .utf8) == "unrelated replacement")
        #expect(try String(contentsOf: holding.appending(path: "source.md"), encoding: .utf8) == "original {title}")
    }

    private func requireSourceBlocked(_ result: DocumentCreationResult) {
        guard case .sourceFailure(_, let error) = result else {
            Issue.record("Ambiguous lifecycle intent must block source-dependent creation")
            return
        }
        #expect(error is LifecycleError)
    }

    private func assertIndependentCreation(_ fixture: PendingCreationFixture, plan: DocumentCreationPlan) throws {
        let workspace = fixture.workspace
        guard
            case .published(let empty) = workspace.createDocument(
                plan, naming: .edited("Empty"), recovery: .createEmptyOnce)
        else { Issue.record("Explicit empty-once creation must not read the ambiguous source"); return }
        #expect(try Data(contentsOf: empty.url).isEmpty)
        let unrelated = try workspace.prepareDocument(in: fixture.unrelated, filenamePattern: "Unrelated")
        guard case .published(let plain) = workspace.createDocument(unrelated, naming: .generated) else {
            Issue.record("Unrelated untemplated creation must remain available")
            return
        }
        #expect(try Data(contentsOf: plain.url).isEmpty)
    }
}

@MainActor private struct PendingCreationFixture {
    let scratch: Scratch
    let workspace: Workspace
    let library: ProjectLibrary
    let source: URL
    let movedSource: URL
    let destination: URL
    let unrelated: URL
    let stalePlan: DocumentCreationPlan

    init(replacement: Data) async throws {
        let scratch = try Scratch()
        self.scratch = scratch
        let (original, library) = try await scratch.workspace(files: ["source.md": "original {title}"])
        source = scratch.url.appending(path: "notes/source.md")
        let owner = try scratch.folder("notes/owner")
        destination = try scratch.folder("notes/owner/child")
        unrelated = try scratch.folder("notes/unrelated")
        let holding = try scratch.folder("notes/holding")
        movedSource = holding.appending(path: "source.md")
        try original.assignTemplate(source, to: owner)
        stalePlan = try original.prepareDocument(in: destination, filenamePattern: "New")
        var intent = Data()
        original.lifecycleOperations.move = { url, folder in
            intent = try Data(contentsOf: library.storageURL)
            return try FileOperations.move(url, into: folder)
        }
        #expect(original.move(source, into: holding).error == nil)
        original.deactivate()
        try intent.write(to: library.storageURL, options: .atomic)
        try replacement.write(to: source)
        self.library = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        workspace = Workspace(projectID: original.projectID, library: self.library)
        workspace.activate()
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(workspace.lastError != nil)
    }
}
