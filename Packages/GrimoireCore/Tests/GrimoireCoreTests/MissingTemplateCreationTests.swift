import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct MissingTemplateCreationTests {
    @Test(arguments: [false, true])
    func failedRetirementSaveBlocksOnlyAffectedCreation(useSource: Bool) async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/posts").resolvingSymlinksInPath().standardizedFileURL
        let unrelated = try scratch.folder("notes/unrelated")
        let source = root.appending(path: "source.md")
        try workspace.assignTemplate(source, to: root)
        if useSource {
            try workspace.assignTemplate(source, to: owner)
        } else {
            try workspace.disableTemplate(in: owner)
        }
        let stale = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        let before = library.projects
        let bytes = try Data(contentsOf: library.storageURL)
        try FileManager.default.removeItem(at: owner)
        try withBlockedWrites(to: ProjectStore(fileURL: library.storageURL)) { () throws in
            #expect(throws: (any Error).self) { try workspace.effectiveTemplateAssignment(for: owner) }
            #expect(throws: (any Error).self) { try workspace.prepareDocument(in: owner, filenamePattern: "New") }
            guard case .contextUnavailable = workspace.createDocument(stale, naming: .generated) else {
                Issue.record("A failed inactive-state save must not reuse the stale active choice")
                return
            }
            #expect(!FileManager.default.fileExists(atPath: owner.path))
            #expect(library.projects == before)
            #expect(try Data(contentsOf: library.storageURL) == bytes)
            #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == before)
            let independent = try workspace.prepareDocument(in: unrelated, filenamePattern: "Independent")
            guard case .published(let created) = workspace.createDocument(independent, naming: .generated) else {
                Issue.record("An unrelated destination must not depend on persisting this missing owner")
                return
            }
            #expect(try String(contentsOf: created.url, encoding: .utf8) == "saved")
        }
        let fresh = try workspace.prepareDocument(in: owner, filenamePattern: "New")
        #expect(workspace.unresolvedTemplateAssignments.count == 1)
        #expect(!FileManager.default.fileExists(atPath: owner.path))
        guard case .published(let created) = workspace.createDocument(fresh, naming: .generated) else {
            Issue.record("Restored settings access must allow explicit retry with ancestor inheritance")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == "saved")
        #expect(try String(contentsOf: source, encoding: .utf8) == "saved")
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }

    @Test(arguments: [false, true], [(false, false), (false, true), (true, false), (true, true)])
    func sameTurnCreationCannotReactivateADeletedOwner(useSource: Bool, scenario: (ancestor: Bool, stale: Bool))
        async throws
    {
        let (ancestor, stale) = scenario
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: [
            "source.md": "old source", "ancestor.md": "ancestor",
        ])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let owner = try scratch.folder("notes/posts").resolvingSymlinksInPath().standardizedFileURL
        let source = root.appending(path: "source.md")
        if ancestor { try workspace.assignTemplate(root.appending(path: "ancestor.md"), to: root) }
        if useSource {
            try workspace.assignTemplate(source, to: owner)
        } else {
            try workspace.disableTemplate(in: owner)
        }
        let original = try #require(try workspace.templateAssignment(for: owner))
        let old = try stale ? workspace.prepareDocument(in: owner, filenamePattern: "New") : nil
        try FileManager.default.removeItem(at: owner)
        // No await or manual refresh: creation itself must preserve the disappearance evidence.
        var plan = try old ?? workspace.prepareDocument(in: owner, filenamePattern: "New")
        if stale {
            guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
                Issue.record("A stale active choice must require review before recreating its owner")
                return
            }
            plan = updated
        }
        var inactive = original
        inactive.state = .unresolved
        #expect(workspace.project?.templateAssignments.contains(inactive) == true)
        #expect(
            ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).project(workspace.projectID)?
                .templateAssignments.contains(inactive) == true)
        #expect(!FileManager.default.fileExists(atPath: owner.path))
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("The reviewed destination must support inactive-owner inheritance or legacy empty creation")
            return
        }
        #expect(try String(contentsOf: created.url, encoding: .utf8) == (ancestor ? "ancestor" : ""))
        #expect(try String(contentsOf: source, encoding: .utf8) == "old source")
        workspace.refreshTemplateAssignments()
        #expect(workspace.project?.templateAssignments.contains(inactive) == true)
        #expect(try workspace.templateAssignment(for: owner) == inactive)
        #expect(ProjectLibrary(store: ProjectStore(fileURL: library.storageURL)).projects == library.projects)
    }
}
