import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct OpenDocumentTests {
    @Test func autosavesAfterAPause() async throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "# Page\n")
        let document = try OpenDocument(url: file, autosaveDelay: .milliseconds(50))
        defer { document.close() }
        #expect(!document.isDirty)

        document.text = "# Page\n\nInk.\n"
        #expect(document.isDirty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Page\n")
        try await until { !document.isDirty }
        #expect(try String(contentsOf: file, encoding: .utf8) == "# Page\n\nInk.\n")
    }

    @Test func saveWritesAtOnceAndOpeningNeverWrites() throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "a")
        let before = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[
            .modificationDate]
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(60))
        defer { document.close() }
        document.save()
        let after = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[
            .modificationDate]
        #expect(before as? Date == after as? Date)

        document.text = "b"
        document.save()
        #expect(try String(contentsOf: file, encoding: .utf8) == "b")
    }

    @Test func reloadsOutsideEditsWhenClean() async throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "mine")
        let document = try OpenDocument(url: file)
        defer { document.close() }
        try await Task.sleep(for: .milliseconds(300))
        try scratch.file("page.md", "theirs")
        try await until { document.text == "theirs" }
        #expect(!document.isDirty)
        #expect(document.conflict == nil)
    }

    @Test func flagsAConflictWhenBothSidesChanged() throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "original")
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(60))
        defer { document.close() }
        document.text = "mine"
        try scratch.file("page.md", "theirs")
        document.checkDisk()
        #expect(document.conflict == "theirs")

        document.save()
        #expect(try String(contentsOf: file, encoding: .utf8) == "theirs")

        document.keepMine()
        #expect(document.conflict == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "mine")
    }

    @Test func loadTheirsTakesTheDiskText() throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "original")
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(60))
        defer { document.close() }
        document.text = "mine"
        try scratch.file("page.md", "theirs")
        document.checkDisk()
        document.loadTheirs()
        #expect(document.text == "theirs")
        #expect(!document.isDirty)
    }

    @Test func closeSavesPendingEdits() throws {
        let scratch = try Scratch()
        let file = try scratch.file("page.md", "a")
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(60))
        document.text = "b"
        document.close()
        #expect(try String(contentsOf: file, encoding: .utf8) == "b")
    }
}

@MainActor
func until(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
