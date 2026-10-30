import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct UnresolvedTemplateTests {
    @Test(arguments: [false, true])
    func explicitRecoveryIsStagedAndKeepsBrokenSourceSeparate(remove: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["posts/source.md": "source"])
        defer { workspace.deactivate() }
        let owner = scratch.url.appending(path: "notes/posts")
        try workspace.assignTemplate(owner.appending(path: "source.md"), to: owner)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        let inactive = try #require(workspace.unresolvedTemplateAssignments.first)
        let target = try scratch.folder("notes/relocated")
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        let plan = try workspace.prepareTemplateRecovery(inactive, locating: remove ? nil : target)
        #expect(library.projects == before)
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.confirmTemplateRecovery(plan) }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
        }
        try workspace.confirmTemplateRecovery(plan)
        #expect(workspace.unresolvedTemplateAssignments.isEmpty)
        if remove {
            #expect(workspace.project?.templateAssignments.isEmpty == true)
        } else {
            let recovered = try #require(try workspace.effectiveTemplateAssignment(for: target))
            #expect(recovered.owner.relativePath == "relocated")
            #expect(recovered.choice == inactive.choice)
            let creation = try workspace.prepareDocument(in: target, filenamePattern: "New")
            if case .sourceFailure = workspace.createDocument(creation, naming: .generated) {
            } else {
                Issue.record("Locating an owner must not guess or repair its missing source")
            }
        }
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func missingOwnerStaysInactiveAfterReappearanceAndRelaunch() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "source"])
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        try workspace.assignTemplate(scratch.url.appending(path: "notes/source.md"), to: owner)
        let original = try #require(workspace.project?.templateAssignments.first)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        var inactive = original
        inactive.state = .unresolved
        #expect(workspace.project?.templateAssignments == [inactive])
        try FileManager.default.createDirectory(at: owner, withIntermediateDirectories: true)
        workspace.refreshTemplateAssignments()
        #expect(try workspace.effectiveTemplateAssignment(for: owner) == nil)
        let restarted = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        let reopened = Workspace(projectID: workspace.projectID, library: restarted)
        reopened.activate()
        defer { reopened.deactivate() }
        #expect(reopened.project?.templateAssignments == [inactive])
        #expect(try reopened.effectiveTemplateAssignment(for: owner) == nil)
    }

    @Test func failedDetectionCommitIsAtomicAndSourceLossDoesNotUnresolveItsOwner() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let first = try scratch.folder("notes/first")
        let second = try scratch.folder("notes/second")
        try workspace.disableTemplate(in: first)
        try workspace.disableTemplate(in: second)
        try workspace.assignTemplate(root.appending(path: "source.md"), to: root)
        try FileManager.default.removeItem(at: first)
        try FileManager.default.removeItem(at: second)
        try FileManager.default.removeItem(at: root.appending(path: "source.md"))
        let before = library.projects
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) {
            workspace.refreshTemplateAssignments()
            #expect(workspace.lastError != nil)
            #expect(library.projects == before)
            #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
        }
        workspace.refreshTemplateAssignments()
        #expect(workspace.unresolvedTemplateAssignments.count == 2)
        #expect(try workspace.templateAssignment(for: root)?.state == .active)
        let plan = try workspace.prepareDocument(in: root, filenamePattern: "New")
        if case .sourceFailure = workspace.createDocument(plan, naming: .generated) {
        } else {
            Issue.record("External source loss must retain broken-source recovery")
        }
    }

    @Test(arguments: ["root", "ancestor", "bookmark", "replaced root", "dangling link"])
    func unavailableAccessIsNotProofOfMissingOwner(scenario: String) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace()
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let ancestor = try scratch.folder("notes/parent")
        let owner = try scratch.folder("notes/parent/posts")
        try workspace.disableTemplate(in: owner)
        let choice = workspace.project?.templateAssignments
        if scenario == "bookmark" {
            try library.update(workspace.projectID) { $0.roots[0].bookmark = Data([0]) }
            workspace.sync()
        } else if scenario == "replaced root" {
            try FileManager.default.moveItem(at: root, to: scratch.url.appending(path: "original"))
            try scratch.folder("notes")
        } else if scenario == "dangling link" {
            try FileManager.default.removeItem(at: ancestor)
            try FileManager.default.createSymbolicLink(
                at: ancestor, withDestinationURL: scratch.url.appending(path: "gone"))
        } else {
            let inaccessible = scenario == "root" ? root : ancestor
            try FileManager.default.removeItem(at: owner)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inaccessible.path)
        }
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ancestor.path)
        }
        workspace.refreshTemplateAssignments()
        #expect(workspace.project?.templateAssignments == choice)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test func locateRejectsConflictsOutsideAccessAndChangedPickerIdentity() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace()
        defer { workspace.deactivate() }
        let owner = try scratch.folder("notes/posts")
        let target = try scratch.folder("notes/new")
        let outside = try scratch.folder("outside")
        try workspace.disableTemplate(in: owner)
        try FileManager.default.removeItem(at: owner)
        workspace.refreshTemplateAssignments()
        let inactive = try #require(workspace.unresolvedTemplateAssignments.first)
        let before = library.projects
        #expect(throws: (any Error).self) { try workspace.prepareTemplateRecovery(inactive, locating: outside) }
        let alias = scratch.url.appending(path: "notes/escape")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try workspace.prepareTemplateRecovery(inactive, locating: alias) }
        let plan = try workspace.prepareTemplateRecovery(inactive, locating: target)
        try FileManager.default.moveItem(at: target, to: scratch.url.appending(path: "held"))
        try scratch.folder("notes/new")
        #expect(throws: (any Error).self) { try workspace.confirmTemplateRecovery(plan) }
        #expect(library.projects == before)
        try workspace.disableTemplate(in: target)
        let conflicting = library.projects
        #expect(throws: (any Error).self) { try workspace.prepareTemplateRecovery(inactive, locating: target) }
        #expect(library.projects == conflicting)
    }
}
