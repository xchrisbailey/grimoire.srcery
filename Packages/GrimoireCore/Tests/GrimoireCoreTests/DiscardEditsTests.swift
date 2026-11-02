import Foundation
import Testing

@testable import GrimoireCore

private struct DiskRefusedWrite: Error {}

@MainActor @Suite struct DiscardEditsTests {
    /// A document whose save always fails, standing in for a volume that went read-only.
    private func failingDocument(_ scratch: Scratch, versions: VersionStore?) throws -> (OpenDocument, URL) {
        let file = try scratch.file("page.md", "on disk")
        let document = try OpenDocument(
            url: file, autosaveDelay: .seconds(3600), authorizeWrite: { _ in throw DiskRefusedWrite() })
        document.versions = versions
        document.text = "my edits"
        return (document, file)
    }

    private func conflictedDocument(_ scratch: Scratch, versions: VersionStore?) throws -> (OpenDocument, URL) {
        let file = try scratch.file("page.md", "original")
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(3600))
        document.versions = versions
        document.text = "my edits"
        try scratch.file("page.md", "theirs")
        document.checkDisk()
        return (document, file)
    }

    @Test func refusalExplainsAConflictAndLeavesFileAndBufferAlone() throws {
        let scratch = try Scratch()
        let store = VersionStore(folder: scratch.url.appending(path: "versions"))
        let (document, file) = try conflictedDocument(scratch, versions: store)
        defer { document.discard() }

        #expect(!document.close())
        guard case .conflict = document.releaseRefusal else {
            Issue.record("Expected a conflict refusal, got \(String(describing: document.releaseRefusal))")
            return
        }
        // Keep Editing is the absence of any further call: everything stays as the refusal found it.
        #expect(!document.close())
        #expect(document.text == "my edits" && document.isDirty)
        #expect(document.conflict == "theirs")
        #expect(try String(contentsOf: file, encoding: .utf8) == "theirs")
        #expect(store.versions(of: file).isEmpty)
    }

    @Test func refusalExplainsAPersistentSaveFailure() throws {
        let scratch = try Scratch()
        let (document, file) = try failingDocument(scratch, versions: nil)
        defer { document.discard() }

        #expect(!document.close())
        guard case .saveFailed(let error) = document.releaseRefusal else {
            Issue.record("Expected a save failure, got \(String(describing: document.releaseRefusal))")
            return
        }
        #expect(error is DiskRefusedWrite)
        #expect(document.text == "my edits" && document.isDirty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "on disk")
    }

    @Test func aPendingMoveOrTrashIsNotOfferedForDiscarding() throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "on disk")
        let document = try OpenDocument(
            url: file, autosaveDelay: .seconds(3600), authorizeWrite: { _ in throw LifecycleError.pendingRepair })
        defer { document.discard() }
        document.text = "my edits"

        #expect(!document.close())
        #expect(document.saveError != nil)
        #expect(document.releaseRefusal == nil)
    }

    @Test(arguments: [true, false])
    func discardKeepsTheBufferAsAVersionBeforeLettingGo(conflict: Bool) throws {
        let scratch = try Scratch()
        let store = VersionStore(folder: scratch.url.appending(path: "versions"))
        let (document, file) =
            try conflict ? conflictedDocument(scratch, versions: store) : failingDocument(scratch, versions: store)
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        #expect(!document.close())

        #expect(document.discardEdits() == .discarded)

        let kept = try #require(store.versions(of: file).first)
        #expect(kept.reason == .discard)
        #expect(store.text(of: kept, for: file) == "my edits")
        #expect(try String(contentsOf: file, encoding: .utf8) == onDisk)
        // Nothing is left to refuse the release, and closing does not write.
        #expect(document.close())
        #expect(try String(contentsOf: file, encoding: .utf8) == onDisk)
    }

    @Test func discardIsRefusedWhenTheVersionCannotBeKept() throws {
        let scratch = try Scratch()
        // A regular file where the store's folder should be makes every write fail.
        let blocker = try scratch.file("blocked", "not a folder")
        let store = VersionStore(folder: blocker.appending(path: "versions"))
        let (document, file) = try failingDocument(scratch, versions: store)
        defer { document.discard() }
        #expect(!document.close())

        #expect(document.discardEdits() == .versionNotKept)

        #expect(document.text == "my edits" && document.isDirty)
        #expect(document.saveError != nil)
        guard case .saveFailed = document.releaseRefusal else {
            Issue.record("The refusal should still stand")
            return
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "on disk")
    }

    @Test func theUserCanDiscardWithoutAVersionAfterBeingToldItIsLost() throws {
        let scratch = try Scratch()
        let (document, file) = try failingDocument(scratch, versions: nil)
        #expect(!document.close())
        #expect(document.discardEdits() == .versionNotKept)

        #expect(document.discardEdits(requiringKeptVersion: false) == .discarded)

        #expect(document.close())
        #expect(try String(contentsOf: file, encoding: .utf8) == "on disk")
    }

    @Test func aVersionAlreadyKeptAsTheNewestCountsAsKept() throws {
        let scratch = try Scratch()
        let store = VersionStore(folder: scratch.url.appending(path: "versions"))
        let (document, file) = try failingDocument(scratch, versions: store)
        store.keep("my edits", of: file, reason: .edit)
        #expect(!document.close())

        #expect(document.discardEdits() == .discarded)
        #expect(store.versions(of: file).count == 1)
    }
}
