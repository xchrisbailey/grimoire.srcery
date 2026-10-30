import Foundation
import Testing

@testable import GrimoireCore

extension AssignedDocumentCreationTests {
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
