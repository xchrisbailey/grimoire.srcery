import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DocumentRecoveryTests {
    @Test func confirmedInheritedRepairPersistsIndependentlyOfCreationAndOtherReferences() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["old.md": "old", "new.md": "new saved"])
        defer { workspace.deactivate() }
        let root = scratch.url.appending(path: "notes")
        let child = try scratch.folder("notes/posts/drafts")
        let other = try scratch.folder("notes/other")
        let optOut = try scratch.folder("notes/archive")
        let old = root.appending(path: "old.md")
        let replacement = root.appending(path: "new.md")
        try workspace.assignTemplate(old, to: root)
        try workspace.assignTemplate(old, to: other)
        try workspace.disableTemplate(in: optOut)
        let otherChoice = try workspace.templateAssignment(for: other)
        let optOutChoice = try workspace.templateAssignment(for: optOut)
        let plan = try workspace.prepareDocument(in: child, filenamePattern: "Draft")
        try FileManager.default.removeItem(at: old)
        guard case .sourceFailure = workspace.createDocument(plan, naming: .edited("Typed name")) else {
            Issue.record("Inherited broken choice must enter recovery")
            return
        }
        guard case .cancelled = workspace.repairDocumentTemplate(plan, replacement: replacement, confirmed: false) else {
            Issue.record("Scope cancellation must leave the assignment untouched")
            return
        }
        #expect(try workspace.templateAssignment(for: root) == plan.assignment)
        guard case .repaired(let repaired) = workspace.repairDocumentTemplate(plan, replacement: replacement) else {
            Issue.record("Confirmed replacement must repair the supplying ancestor")
            return
        }
        #expect(repaired.id == plan.id)
        #expect(repaired.assignment?.owner == plan.assignment?.owner)
        #expect(try workspace.templateAssignment(for: child) == nil)
        #expect(try workspace.templateAssignment(for: other) == otherChoice)
        #expect(try workspace.templateAssignment(for: optOut) == optOutChoice)
        guard case .cancelled = workspace.createDocument(repaired, naming: .edited("Typed name"), confirmed: false) else {
            Issue.record("Creation cancellation is independent of the committed repair")
            return
        }
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.projects == library.projects)
        let repairedAssignment = try #require(repaired.assignment)
        #expect(relaunched.project(workspace.projectID)?.templateAssignments.contains(repairedAssignment) == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try Data(contentsOf: replacement) == Data("new saved".utf8))
        let next = try workspace.prepareDocument(in: child, filenamePattern: "Next")
        guard case .published(let created) = workspace.createDocument(next, naming: .edited("Typed name")) else {
            Issue.record("The persisted repair must supply the next creation")
            return
        }
        #expect(try Data(contentsOf: created.url) == Data("new saved".utf8))
    }

    @Test func emptyOnceSurvivesDestinationRetryButNotANewCreation() async throws {
        let scratch = try Scratch()
        let (workspace, library) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let before = library.projects
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        try FileManager.default.removeItem(at: source)
        guard case .sourceFailure = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("A broken source must stop normal creation")
            return
        }
        var operations = DocumentCreationOperations()
        operations.write = { handle in
            try handle.write(contentsOf: Data("partial".utf8))
            throw POSIXError(.ENOSPC)
        }
        guard case .failed = workspace.createDocument(
            plan, naming: .edited("Keep me"), recovery: .createEmptyOnce,
            now: .now, calendar: .current, operations: operations)
        else {
            Issue.record("Empty once must use safe publication and report write failure")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        try scratch.file("notes/Keep me.md", "Competitor")
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Keep me")) else {
            Issue.record("Destination retry must retain the pending empty-once choice")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me 2.md")
        #expect(created.editorCaretUTF16 == 0)
        #expect(try Data(contentsOf: created.url).isEmpty)
        #expect(try String(contentsOf: folder.appending(path: "Keep me.md"), encoding: .utf8) == "Competitor")
        #expect(library.projects == before)
        let next = try workspace.prepareDocument(in: folder, filenamePattern: "Next")
        guard case .sourceFailure = workspace.createDocument(next, naming: .generated) else {
            Issue.record("A separate command must use the configured source again")
            return
        }
    }
}
