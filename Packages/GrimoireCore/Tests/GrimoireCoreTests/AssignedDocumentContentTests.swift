import Foundation
import Testing

@testable import GrimoireCore

extension AssignedDocumentCreationTests {
    @Test func reviewedUnassignedDestinationPublishesOnceWithLegacyHandoff() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: [:])
        defer { workspace.deactivate() }
        let folder = try scratch.folder("notes/posts")
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        #expect(!plan.requiresNaming)
        try FileManager.default.moveItem(at: folder, to: scratch.url.appending(path: "notes/old"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        guard case .reviewNeeded(let updated) = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("A replacement destination requires review even without a source")
            return
        }
        #expect(!updated.requiresNaming)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        guard case .published(let created) = workspace.createDocument(updated, naming: .edited("Keep me")) else {
            Issue.record("Confirming reviewed legacy details must publish")
            return
        }
        #expect(created.url.lastPathComponent == "Keep me.md")
        #expect(created.editorCaretUTF16 == nil)
        #expect(try Data(contentsOf: created.url).isEmpty)
        guard case .alreadyPublished(let repeated) = workspace.createDocument(updated, naming: .edited("Keep me"))
        else {
            Issue.record("Repeated confirmation must not publish another document")
            return
        }
        #expect(repeated.url == created.url)
        guard case .alreadyPublished = workspace.createDocument(plan, naming: .generated) else {
            Issue.record("Review must preserve the original pending creation identity")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Keep me.md"])
    }

    @Test func exactAssignmentPublishesSavedStaticBytesAndHandsOffOnce() async throws {
        let scratch = try Scratch()
        let (workspace, _) = try await scratch.workspace(files: ["source.md": "saved"])
        defer { workspace.deactivate() }
        let folder = scratch.url.appending(path: "notes")
        let source = folder.appending(path: "source.md")
        try workspace.assignTemplate(source, to: folder)
        let plan = try workspace.prepareDocument(in: folder, filenamePattern: "Draft")
        #expect(FileIdentity.same(try #require(plan.source), source))
        #expect(plan.suggestedStem == "Draft")
        let bytes = Data("\u{feff}# 🧙\r\n  {title}\rLast  \n\n".utf8)
        try bytes.write(to: source)
        let buffer = try OpenDocument(url: source, autosaveDelay: .seconds(3600))
        buffer.text = "unsaved"
        defer { buffer.discard() }
        guard case .published(let created) = workspace.createDocument(plan, naming: .edited("Élan!")) else {
            Issue.record("Expected publication")
            return
        }
        #expect(created.url.lastPathComponent == "Élan!.md")
        #expect(created.editorCaretUTF16 == 25)
        #expect(try Data(contentsOf: created.url) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        guard case .alreadyPublished = workspace.createDocument(plan, naming: .edited("Élan!")) else {
            Issue.record("A completed creation must not publish twice")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["source.md", "Élan!.md"])
    }
}
