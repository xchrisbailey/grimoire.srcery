import Foundation
import Testing

@testable import GrimoireCore

private enum PendingNameCapability: CaseIterable, Sendable {
    case sensitive, insensitive, unknown
    var value: Bool? {
        switch self {
        case .sensitive: true
        case .insensitive: false
        case .unknown: nil
        }
    }
}

@MainActor @Suite struct LifecyclePendingCaseTests {
    @Test func unknownCaseOnlyRenameStopsBeforeMutation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        defer { workspace.deactivate() }
        let source = scratch.url.appending(path: "notes/source.md")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(source, to: owner)
        workspace.lifecycleOperations.caseSensitiveNames = { _ in nil }
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = workspace.rename(source, to: "SOURCE")
        #expect(result.error != nil)
        #expect(result.movedURL == nil)
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(library.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == bytes)
        let names = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        #expect(names.contains("source.md"))
        #expect(!names.contains("SOURCE.md"))
    }

    @Test(arguments: PendingNameCapability.allCases)
    private func wrongIdentityAtCaseOnlyAliasNeverFinalizes(capability: PendingNameCapability) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        let root = scratch.url.appending(path: "notes")
        let source = root.appending(path: "source.md")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(source, to: owner)
        workspace.lifecycleOperations.caseSensitiveNames = { _ in false }
        var intent = Data()
        workspace.lifecycleOperations.rename = { _, _ in
            intent = try Data(contentsOf: library.storageURL)
            throw CocoaError(.userCancelled)
        }
        _ = workspace.rename(source, to: "SOURCE")
        workspace.deactivate()
        let preserved = scratch.url.appending(path: "preserved.md")
        try FileManager.default.moveItem(at: source, to: preserved)
        let replacement = try scratch.file("notes/SOURCE.md", "replacement")
        try intent.write(to: library.storageURL, options: .atomic)
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let before = relaunched.projects
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.lifecycleOperations.caseSensitiveNames = { _ in capability.value }
        restarted.activate()
        defer { restarted.deactivate() }
        #expect(restarted.hasPendingLifecycleOperations)
        #expect(restarted.lastError != nil)
        #expect(relaunched.projects == before)
        #expect(try Data(contentsOf: library.storageURL) == intent)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "original")
        #expect(try String(contentsOf: replacement, encoding: .utf8) == "replacement")
    }

    @Test(arguments: [false, true], PendingNameCapability.allCases)
    private func missingDestinationAliasBlocksMovementAssignmentAndSourceReads(
        rename: Bool,
        capability: PendingNameCapability
    ) async throws {
        let fixture = try await PendingCaseFixture(capability: capability.value, dependentAlias: true)
        let preserved = fixture.scratch.url.appending(path: "preserved.md")
        try FileManager.default.moveItem(at: fixture.moved, to: preserved)
        fixture.workspace.deactivate()
        let library = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        let workspace = Workspace(projectID: fixture.workspace.projectID, library: library)
        workspace.lifecycleOperations.caseSensitiveNames = { _ in capability.value }
        workspace.activate()
        defer { workspace.deactivate() }
        let target = fixture.moved.deletingLastPathComponent()
        let incoming = try fixture.scratch.file(
            rename ? "notes/target/other.md" : "notes/incoming/SOURCE.md", "unrelated")
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let result = rename ? workspace.rename(incoming, to: "SOURCE") : workspace.move(incoming, into: target)
        let alias = target.appending(path: "SOURCE.md")
        if capability == .sensitive {
            #expect(result.error == nil)
            #expect(result.movedURL != nil)
        } else {
            #expect(result.error != nil)
            #expect(result.movedURL == nil)
            #expect(try String(contentsOf: incoming, encoding: .utf8) == "unrelated")
            #expect(!FileManager.default.fileExists(atPath: alias.path))
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
            try Data("unrelated".utf8).write(to: alias)
        }
        let owner = try fixture.scratch.folder("notes/new-owner")
        if capability == .sensitive {
            try workspace.assignTemplate(alias, to: owner)
        } else {
            #expect(throws: (any Error).self) { try workspace.assignTemplate(alias, to: owner) }
        }
        let stale = try #require(fixture.stalePlan)
        let fresh = try workspace.prepareDocument(in: fixture.dependentOwner, filenamePattern: "Fresh")
        try assertAliasCreation(stale: stale, fresh: fresh, in: workspace, capability: capability)
        if capability != .sensitive {
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.dependentOwner.path).isEmpty)
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "original")
        #expect(try String(contentsOf: alias, encoding: .utf8) == "unrelated")
    }

    private func assertAliasCreation(
        stale: DocumentCreationPlan, fresh: DocumentCreationPlan,
        in workspace: Workspace, capability: PendingNameCapability
    ) throws {
        for (plan, name) in [(stale, "Stale"), (fresh, "Fresh")] {
            let created = workspace.createDocument(plan, naming: .edited(name))
            if capability == .sensitive {
                guard case .published(let output) = created else {
                    Issue.record("Distinct sensitive names must stay usable"); return
                }
                #expect(try String(contentsOf: output.url, encoding: .utf8) == "unrelated")
            } else {
                guard case .sourceFailure(_, let error) = created else {
                    Issue.record("Reserved aliases must block source reads"); return
                }
                #expect(error is LifecycleError)
            }
        }
    }

    @Test(arguments: [false, true], PendingNameCapability.allCases)
    private func prospectiveAliasOfReservedSourceIsPreflighted(rename: Bool, capability: PendingNameCapability)
        async throws
    {
        let fixture = try await PendingCaseFixture(capability: capability.value)
        let workspace = fixture.workspace
        defer { workspace.deactivate() }
        let incoming = try fixture.scratch.file(rename ? "notes/plain.md" : "notes/incoming/SOURCE.md", "independent")
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        let result = rename ? workspace.rename(incoming, to: "SOURCE") : workspace.move(incoming, into: fixture.root)
        if capability == .sensitive {
            #expect(result.error == nil)
            #expect(result.movedURL != nil)
        } else {
            #expect(result.error != nil)
            #expect(result.movedURL == nil)
            #expect(result.legacyMovedURL == nil)
            #expect(try String(contentsOf: incoming, encoding: .utf8) == "independent")
            #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "SOURCE.md").path))
        }
        #expect(fixture.library.projects == before)
        #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        workspace.reconcileLifecycleOperations()
        #expect(!workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == "original")
    }

    @Test(arguments: PendingNameCapability.allCases)
    private func replacementAtCaseAliasIsOccupiedDuringRestart(capability: PendingNameCapability) async throws {
        let fixture = try await PendingCaseFixture(capability: capability.value)
        let replacement = try fixture.scratch.file("notes/SOURCE.md", "unrelated replacement")
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        fixture.workspace.deactivate()
        let library = ProjectLibrary(store: ProjectStore(fileURL: fixture.library.storageURL))
        let restarted = Workspace(projectID: fixture.workspace.projectID, library: library)
        restarted.lifecycleOperations.caseSensitiveNames = { _ in capability.value }
        restarted.activate()
        defer { restarted.deactivate() }
        if capability == .sensitive {
            #expect(!restarted.hasPendingLifecycleOperations)
            #expect(restarted.lastError == nil)
        } else {
            #expect(restarted.hasPendingLifecycleOperations)
            #expect(restarted.lastError != nil)
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        #expect(try String(contentsOf: replacement, encoding: .utf8) == "unrelated replacement")
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == "original")
    }

    @Test(arguments: [false, true], PendingNameCapability.allCases)
    private func genuineCaseOnlyIntentReconcilesOnlyWithKnownNames(
        completed: Bool,
        capability: PendingNameCapability
    ) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/owner")
        try workspace.assignTemplate(root.appending(path: "source.md"), to: owner)
        let before = workspace.project?.templateAssignments
        workspace.lifecycleOperations.caseSensitiveNames = { _ in false }
        var intent = Data()
        workspace.lifecycleOperations.rename = { url, name in
            intent = try Data(contentsOf: library.storageURL)
            if completed { return try FileOperations.rename(url, to: name) }
            throw CocoaError(.userCancelled)
        }
        _ = workspace.rename(root.appending(path: "source.md"), to: "SOURCE")
        workspace.deactivate()
        try intent.write(to: library.storageURL, options: .atomic)
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let restarted = Workspace(projectID: workspace.projectID, library: relaunched)
        restarted.lifecycleOperations.caseSensitiveNames = { _ in capability.value }
        restarted.activate()
        defer { restarted.deactivate() }
        if capability == .unknown {
            #expect(restarted.hasPendingLifecycleOperations)
            #expect(restarted.lastError != nil)
            #expect(restarted.project?.templateAssignments == before)
            #expect(try Data(contentsOf: library.storageURL) == intent)
        } else {
            #expect(!restarted.hasPendingLifecycleOperations)
            #expect(restarted.lastError == nil)
            let rootID = try #require(restarted.project?.roots.first?.id)
            let expected = FileReference(rootID: rootID, relativePath: completed ? "SOURCE.md" : "source.md")
            #expect(try restarted.templateAssignment(for: owner)?.choice == .useSource(expected))
        }
        #expect(
            try String(contentsOf: root.appending(path: completed ? "SOURCE.md" : "source.md"), encoding: .utf8)
                == "original")
    }
}

@MainActor @Suite struct LifecyclePendingLibraryCaseTests {
    @Test func directLibraryAliasAssignmentUsesActualVolumeSemantics() async throws {
        let fixture = try await PendingCaseFixture(capability: nil)
        defer { fixture.workspace.deactivate() }
        try fixture.scratch.file("notes/SOURCE.md", "replacement")
        try fixture.scratch.folder("notes/another-owner")
        let rootID = try #require(fixture.workspace.project?.roots.first?.id)
        let choice = FolderTemplateAssignment(
            owner: FileReference(rootID: rootID, relativePath: "another-owner"),
            choice: .useSource(FileReference(rootID: rootID, relativePath: "SOURCE.md")))
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        let sensitive = (try? fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames
        if sensitive == true {
            try fixture.library.update(fixture.workspace.projectID) { $0.templateAssignments.append(choice) }
            #expect(fixture.workspace.project?.templateAssignments.contains(choice) == true)
        } else {
            #expect(throws: (any Error).self) {
                try fixture.library.update(fixture.workspace.projectID) { $0.templateAssignments.append(choice) }
            }
            #expect(fixture.library.projects == before)
            #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        }
        #expect(fixture.workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: fixture.moved, encoding: .utf8) == "original")
    }

    @Test func directPendingInsertionCannotReserveAnEquivalentPathTwice() async throws {
        let fixture = try await PendingCaseFixture(capability: nil)
        defer { fixture.workspace.deactivate() }
        let plain = try fixture.scratch.file("notes/plain.md", "independent")
        let owner = try fixture.scratch.folder("notes/second-owner")
        try fixture.workspace.assignTemplate(plain, to: owner)
        var project = try #require(fixture.workspace.project)
        project.pendingLifecycleOperations = []
        let store = ProjectStore(fileURL: fixture.scratch.url.appending(path: "candidate.json"))
        try store.save([project])
        let isolated = Workspace(projectID: project.id, library: ProjectLibrary(store: store))
        isolated.activate()
        var candidate: PendingLifecycleOperation?
        isolated.lifecycleOperations.rename = { _, _ in
            candidate = try store.load().first?.pendingLifecycleOperations.first
            throw CocoaError(.userCancelled)
        }
        _ = isolated.rename(plain, to: "SOURCE")
        isolated.deactivate()
        let captured = try #require(candidate)
        let before = fixture.library.projects
        let bytes = try Data(contentsOf: fixture.library.storageURL)
        let sensitive = (try? fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames
        if sensitive == true {
            try fixture.library.update(project.id) { $0.pendingLifecycleOperations.append(captured) }
            #expect(fixture.workspace.project?.pendingLifecycleOperations.count == 2)
        } else {
            #expect(throws: (any Error).self) {
                try fixture.library.update(project.id) { $0.pendingLifecycleOperations.append(captured) }
            }
            #expect(fixture.library.projects == before)
            #expect(try Data(contentsOf: fixture.library.storageURL) == bytes)
        }
        fixture.workspace.reconcileLifecycleOperations()
        #expect(!fixture.workspace.hasPendingLifecycleOperations)
        #expect(try String(contentsOf: plain, encoding: .utf8) == "independent")
    }
}

@MainActor private struct PendingCaseFixture {
    let scratch: Scratch
    let workspace: Workspace
    let library: ProjectLibrary
    let root: URL
    let moved: URL
    let dependentOwner: URL
    let stalePlan: DocumentCreationPlan?

    init(capability: Bool?, dependentAlias: Bool = false) async throws {
        let scratch = try Scratch()
        self.scratch = scratch
        (workspace, library) = try await scratch.workspace(files: ["source.md": "original"])
        root = scratch.url.appending(path: "notes")
        let target = try scratch.folder("notes/target")
        moved = target.appending(path: "source.md")
        let owner = try scratch.folder("notes/owner")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: owner)
        dependentOwner = try scratch.folder("notes/dependent-owner")
        if dependentAlias {
            let rootID = try #require(workspace.project?.roots.first?.id)
            try library.update(workspace.projectID) {
                $0.templateAssignments.append(
                    FolderTemplateAssignment(
                        owner: FileReference(rootID: rootID, relativePath: "dependent-owner"),
                        choice: .useSource(FileReference(rootID: rootID, relativePath: "target/SOURCE.md"))))
            }
            stalePlan = try workspace.prepareDocument(in: dependentOwner, filenamePattern: "Stale")
        } else {
            stalePlan = nil
        }
        workspace.lifecycleOperations.caseSensitiveNames = { _ in capability }
        let directory = library.storageURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            workspace.lifecycleOperations.move = { try FileOperations.move($0, into: $1) }
        }
        workspace.lifecycleOperations.move = { url, folder in
            let result = try FileOperations.move(url, into: folder)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            return result
        }
        let result = workspace.move(source, into: target)
        #expect(result.movedURL != nil)
        #expect(result.error != nil)
        #expect(workspace.hasPendingLifecycleOperations)
    }
}
