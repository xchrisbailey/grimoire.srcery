import Foundation
import Testing

@testable import GrimoireCore

@Suite struct VersionStoreTests {
    func makeStore(_ scratch: Scratch) -> VersionStore {
        VersionStore(folder: scratch.url.appending(path: "Versions"))
    }

    @Test func keepsTheTextBeforeTheFirstSaveAfterAPause() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let file = scratch.url.appending(path: "potions.md")
        let start = Date(timeIntervalSince1970: 1_000_000)
        store.willSave(file, previous: "one", now: start)
        store.willSave(file, previous: "two", now: start.addingTimeInterval(30))
        store.willSave(file, previous: "three", now: start.addingTimeInterval(30 + 200))
        let versions = store.versions(of: file)
        #expect(versions.map { store.text(of: $0, for: file) } == ["three", "one"])
        #expect(versions.allSatisfy { $0.reason == .edit })
    }

    @Test func skipsDuplicatesAndKeepsReasons() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let file = scratch.url.appending(path: "potions.md")
        store.keep("ink", of: file, reason: .replaceAll)
        #expect(store.keep("ink", of: file, reason: .replaceAll) == nil)
        store.keep("ink 2", of: file, reason: .externalChange)
        #expect(store.versions(of: file).map(\.reason) == [.externalChange, .replaceAll])
        // Another store over the same folder reads the same history.
        #expect(makeStore(scratch).versions(of: file).count == 2)
    }

    @Test func prunesByAgeAndCountButKeepsTheNewestFew() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        store.maxCount = 5
        store.minimumKept = 2
        store.maxAge = 100
        let file = scratch.url.appending(path: "potions.md")
        let start = Date(timeIntervalSince1970: 0)
        for number in 0..<8 {
            store.keep("v\(number)", of: file, reason: .edit, now: start.addingTimeInterval(Double(number)))
        }
        #expect(store.versions(of: file).count == 5)
        store.keep("late", of: file, reason: .edit, now: start.addingTimeInterval(10_000))
        let kept = store.versions(of: file).map { store.text(of: $0, for: file) }
        #expect(kept == ["late", "v7"])
    }

    @Test func historyFollowsAMove() throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let old = scratch.url.appending(path: "potions.md")
        let new = scratch.url.appending(path: "brews/potions.md")
        store.keep("ink", of: old, reason: .edit)
        store.move(from: old, to: new)
        #expect(store.versions(of: old).isEmpty)
        #expect(store.versions(of: new).count == 1)
    }

    @MainActor @Test func theOpenDocumentKeepsVersions() async throws {
        let scratch = try Scratch()
        let store = makeStore(scratch)
        let file = try scratch.file("notes/potions.md", "first\n")
        let document = try OpenDocument(url: file, autosaveDelay: .seconds(60))
        document.versions = store
        document.text = "second\n"
        document.save()
        #expect(store.versions(of: file).compactMap { store.text(of: $0, for: file) } == ["first\n"])
        // Another app rewrites the file; the text it replaced is kept.
        try Data("third\n".utf8).write(to: file)
        document.checkDisk()
        #expect(document.text == "third\n")
        #expect(store.versions(of: file).first?.reason == .externalChange)
        #expect(store.versions(of: file).first.flatMap { store.text(of: $0, for: file) } == "second\n")
        document.keepVersion(.replaceAll)
        #expect(store.versions(of: file).first?.reason == .replaceAll)
        document.close()
    }
}

@Suite struct LineDiffTests {
    @Test func showsAddedAndRemovedLinesWithContext() {
        let old = (1...20).map { "line \($0)" }.joined(separator: "\n")
        var lines = (1...20).map { "line \($0)" }
        lines[9] = "changed 10"
        lines.insert("new", at: 15)
        let diff = LineDiff(from: old, to: lines.joined(separator: "\n"), context: 1)
        #expect(diff.added == 2)
        #expect(diff.removed == 1)
        #expect(diff.lines.first?.kind == .skipped(8))
        #expect(diff.lines.contains { $0.kind == .removed && $0.text == "line 10" })
        #expect(diff.lines.contains { $0.kind == .added && $0.text == "changed 10" })
        #expect(LineDiff(from: "same", to: "same").isEmpty)
    }
}

@Suite struct GitBaselineTests {
    func git(_ arguments: [String], in folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.currentDirectoryURL = folder
        process.arguments =
            ["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    @Test func readsCommittedTextFromLooseObjectsAndPacks() throws {
        let scratch = try Scratch()
        let repo = try scratch.folder("repo")
        try git(["init", "-q", "-b", "main"], in: repo)
        let file = try scratch.file("repo/notes/potions.md", "# Potions\n\nInk of recall.\n")
        try git(["add", "."], in: repo)
        try git(["commit", "-q", "-m", "first"], in: repo)
        try Data("# Potions\n\nInk of recall, edited.\n".utf8).write(to: file)
        #expect(GitBaseline.committedText(of: file) == "# Potions\n\nInk of recall.\n")

        // A second commit, then pack everything so the blob is a delta in a pack.
        let long = (1...200).map { "Line \($0) of the ledger." }.joined(separator: "\n")
        try Data((long + "\n").utf8).write(to: file)
        try git(["commit", "-q", "-am", "second"], in: repo)
        try Data((long + "\nmore\n").utf8).write(to: file)
        try git(["commit", "-q", "-am", "third"], in: repo)
        try git(["gc", "-q", "--aggressive"], in: repo)
        #expect(GitBaseline.committedText(of: file) == long + "\nmore\n")
    }

    @Test func returnsNilOutsideARepository() throws {
        let scratch = try Scratch()
        let file = try scratch.file("loose.md", "ink")
        #expect(GitBaseline.committedText(of: file) == nil)
    }
}
