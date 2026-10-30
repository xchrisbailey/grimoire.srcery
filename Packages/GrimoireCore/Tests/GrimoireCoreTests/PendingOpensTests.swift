import Foundation
import Testing

@testable import GrimoireCore

@Suite struct PendingOpensTests {
    private let first = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/a.md")])
    private let second = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/b.md")])

    @MainActor @Test func finderRequestsWaitForProjectLoadRecovery() throws {
        let scratch = try Scratch()
        let folder = try scratch.folder("notes")
        let boundFile = try scratch.file("notes/requested.md", "# Requested")
        let looseFile = try scratch.file("loose.md", "# Loose")
        let file = scratch.url.appending(path: "projects.json")
        let store = ProjectStore(fileURL: file)
        let original = ProjectLibrary(store: store)
        let project = original.createProject(named: "Recovered")
        try original.bindFolder(folder, to: project.id)
        let savedProjects = try store.load()
        let backup = try Data(contentsOf: file)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: file)

        let library = ProjectLibrary(store: store)
        var pending = PendingOpens()
        for placement in pending.place([boundFile, looseFile], in: library, unsortedName: "Unsorted") {
            pending.add(placement)
        }
        #expect(library.projects.isEmpty)
        #expect(pending.windowsToRequest() == 0)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        #expect(try Data(contentsOf: file) == corrupt)

        library.retryLoad()
        #expect(library.loadError != nil)
        #expect(pending.place([boundFile], in: library, unsortedName: "Unsorted").isEmpty)
        #expect(try Data(contentsOf: file) == corrupt)

        try backup.write(to: file)
        library.retryLoad()
        #expect(library.loadError == nil)
        for placement in pending.place([], in: library, unsortedName: "Unsorted") {
            pending.add(placement)
        }
        #expect(pending.windowsToRequest() == 2)
        #expect(pending.claim(preferring: project.id, isNew: false) == .init(projectID: project.id, urls: [boundFile]))
        let claimed = pending.claim(preferring: nil, isNew: true)
        let loosePlacement = try #require(claimed)
        let unsorted = try #require(library.unsortedProject)
        #expect(loosePlacement == .init(projectID: unsorted.id, urls: [looseFile]))
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        #expect(library.project(project.id) == savedProjects.first)
        #expect(try store.load() == library.projects)
        let bookmark = try #require(unsorted.looseFiles.first).bookmark
        #expect(
            try FolderBookmark.resolve(bookmark).url.resolvingSymlinksInPath() == looseFile.resolvingSymlinksInPath())
        #expect(pending.place([], in: library, unsortedName: "Unsorted").isEmpty)
    }

    @Test func aNewWindowTakesTheProjectThatHasWaitedLongest() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(second)
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == second)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
    }

    @Test func aRestoredWindowTakesOnlyItsOwnProject() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(second)
        #expect(pending.claim(preferring: UUID(), isNew: false) == nil)
        #expect(pending.claim(preferring: nil, isNew: false) == nil)
        #expect(pending.claim(preferring: second.projectID, isNew: false) == second)
        #expect(pending.claim(preferring: second.projectID, isNew: false) == nil)
        #expect(pending.claim(preferring: first.projectID, isNew: false) == first)
    }

    @Test func filesForAWaitingProjectJoinItsList() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(.init(projectID: first.projectID, urls: [URL(filePath: "/tmp/a.md"), URL(filePath: "/tmp/c.md")]))
        #expect(pending.windowsToRequest() == 1)
        #expect(pending.claim(preferring: nil, isNew: true)?.urls.map(\.lastPathComponent) == ["a.md", "c.md"])
    }

    @Test func oneWindowIsRequestedPerWaitingProject() {
        var pending = PendingOpens()
        #expect(pending.windowsToRequest() == 0)
        pending.add(first)
        pending.add(second)
        #expect(pending.windowsToRequest() == 2)
        #expect(pending.windowsToRequest() == 0)

        // The windows asked for take what waits; nothing more is asked for.
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == second)
        #expect(pending.windowsToRequest() == 0)

        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
    }

    @Test func aNewWindowThatWasNeverAskedForDoesNotMakeTheCountNegative() {
        var pending = PendingOpens()
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
    }

    @Test func aWindowTakenByAnotherNewWindowIsNotRequestedTwice() {
        var pending = PendingOpens()
        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
        // The user opened a window first; it took the files, and the one asked for arrives empty.
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        pending.add(second)
        #expect(pending.windowsToRequest() == 1)
    }
}
