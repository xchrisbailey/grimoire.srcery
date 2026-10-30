import Darwin
import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct DocumentRecoveryTests {
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
