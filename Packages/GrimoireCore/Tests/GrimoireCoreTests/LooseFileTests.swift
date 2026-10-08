import Foundation
import Testing

@testable import GrimoireCore

/// `projects.json` as 1.0.0 beta 2 wrote it: no `kind` and no `looseFiles` on any project.
private let betaTwoProjects = """
    {
      "projects" : [
        {
          "color" : "sparkle",
          "dictionary" : [ "grimoire" ],
          "expandedFolders" : [
            { "relativePath" : "brews", "rootID" : "11111111-1111-1111-1111-111111111111" }
          ],
          "icon" : "book.closed",
          "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "lastOpenedFile" : { "relativePath" : "brews/elixir.md", "rootID" : "11111111-1111-1111-1111-111111111111" },
          "name" : "Potions",
          "overrides" : { "fileExtensions" : [ "md" ], "intelligenceOff" : true },
          "roots" : [
            {
              "alias" : "Brews",
              "bookmark" : "AQID",
              "id" : "11111111-1111-1111-1111-111111111111",
              "lastKnownPath" : "/Users/me/notes",
              "name" : "notes"
            }
          ]
        },
        {
          "color" : "magic",
          "expandedFolders" : [],
          "icon" : "book.closed",
          "id" : "22222222-2222-2222-2222-222222222222",
          "name" : "Empty",
          "roots" : []
        }
      ],
      "version" : 1
    }
    """

@Suite struct LooseFileStoreTests {
    @Test func aFileFromBetaTwoLoadsWithEveryProjectUnchanged() throws {
        let scratch = try Scratch()
        let file = try scratch.file("projects.json", betaTwoProjects)
        let projects = try ProjectStore(fileURL: file).load()

        let rootID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        #expect(
            projects == [
                Project(
                    id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, name: "Potions", color: .sparkle,
                    roots: [
                        FolderRoot(
                            id: rootID, name: "notes", alias: "Brews", bookmark: Data([1, 2, 3]),
                            lastKnownPath: "/Users/me/notes")
                    ],
                    lastOpenedFile: FileReference(rootID: rootID, relativePath: "brews/elixir.md"),
                    expandedFolders: [FileReference(rootID: rootID, relativePath: "brews")],
                    overrides: ProjectOverrides(fileExtensions: ["md"], intelligenceOff: true),
                    dictionary: ["grimoire"]),
                Project(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Empty"),
            ])
        #expect(projects.allSatisfy { $0.kind == .standard && $0.looseFiles.isEmpty })
    }

    @Test func kindAndLooseFilesSurviveSavingAndLoading() throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "projects.json"))
        let project = Project(
            name: "Unsorted", icon: "tray",
            looseFiles: [LooseFile(name: "spell.md", bookmark: Data([4, 5]), lastKnownPath: "/tmp/spell.md")],
            kind: .unsorted)
        try store.save([project])
        #expect(try store.load() == [project])
    }
}

@MainActor @Suite struct PlacementTests {
    private func library(_ scratch: Scratch) -> ProjectLibrary {
        ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
    }

    @Test func aFileUnderAProjectFolderBelongsToThatProject() throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("notes")
        let page = try scratch.file("notes/brews/elixir.md")
        let library = library(scratch)
        let project = library.createProject(named: "Potions")
        try library.bindFolder(notes, to: project.id)

        let placements = library.place([page], unsortedName: "Unsorted")
        #expect(placements == [.init(projectID: project.id, urls: [page])])
        #expect(library.unsortedProject == nil)
        #expect(library.projects.count == 1)
    }

    @Test func aLooseFileGoesToUnsortedWhichIsCreatedOnceAndReused() throws {
        let scratch = try Scratch()
        let first = try scratch.file("elsewhere/one.md")
        let second = try scratch.file("elsewhere/two.md")
        let library = library(scratch)

        let firstPlacement = library.place([first], unsortedName: "Unsorted")
        let unsorted = try #require(library.unsortedProject)
        #expect(firstPlacement == [.init(projectID: unsorted.id, urls: [first])])
        #expect(unsorted.name == "Unsorted")

        library.place([first], unsortedName: "Unsorted")
        library.place([second], unsortedName: "Unsorted")
        #expect(library.projects.count == 1)
        #expect(library.unsortedProject?.looseFiles.map(\.name) == ["one.md", "two.md"])
    }

    @Test func unsortedIsFoundByKindEvenAfterARename() throws {
        let scratch = try Scratch()
        let first = try scratch.file("elsewhere/one.md")
        let second = try scratch.file("elsewhere/two.md")
        let library = library(scratch)
        library.place([first], unsortedName: "Unsorted")
        let id = try #require(library.unsortedProject?.id)
        library.update(id) { $0.name = "Strays" }

        library.place([second], unsortedName: "Nicht sortiert")
        #expect(library.projects.map(\.name) == ["Strays"])
        #expect(library.unsortedProject?.looseFiles.count == 2)
    }

    @Test func deletingUnsortedLetsTheNextLooseFileMakeANewOne() throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/one.md")
        let library = library(scratch)
        library.place([page], unsortedName: "Unsorted")
        let old = try #require(library.unsortedProject?.id)
        library.deleteProject(old)

        library.place([page], unsortedName: "Unsorted")
        let unsorted = try #require(library.unsortedProject)
        #expect(unsorted.id != old)
        #expect(unsorted.looseFiles.count == 1)
    }

    @Test func severalFilesOfOneProjectShareOnePlacement() throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("notes")
        let pages = try (1...5).map { try scratch.file("notes/page\($0).md") }
        let library = library(scratch)
        let other = library.createProject(named: "Other")
        let project = library.createProject(named: "Notes")
        try library.bindFolder(notes, to: project.id)

        let placements = library.place(pages + [pages[0]], unsortedName: "Unsorted")
        #expect(placements == [.init(projectID: project.id, urls: pages)])
        #expect(library.project(other.id)?.looseFiles.isEmpty == true)
    }

    @Test func theInnermostFolderWins() throws {
        let scratch = try Scratch()
        let outer = try scratch.folder("notes")
        let inner = try scratch.folder("notes/brews")
        let page = try scratch.file("notes/brews/elixir.md")
        let library = library(scratch)
        let wide = library.createProject(named: "Wide")
        let narrow = library.createProject(named: "Narrow")
        try library.bindFolder(outer, to: wide.id)
        try library.bindFolder(inner, to: narrow.id)

        #expect(library.place([page], unsortedName: "Unsorted").map(\.projectID) == [narrow.id])
    }

    @Test func aFolderMovedWhileGrimoireWasClosedStillClaimsItsFiles() throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("notes")
        try scratch.file("notes/elixir.md")
        let library = library(scratch)
        let project = library.createProject(named: "Potions")
        try library.bindFolder(notes, to: project.id)

        let moved = scratch.url.appending(path: "archive/notes", directoryHint: .isDirectory)
        try scratch.folder("archive")
        try FileManager.default.moveItem(at: notes, to: moved)

        // A relaunch reads the stored project, whose stored path is now wrong.
        let relaunched = self.library(scratch)
        let placements = relaunched.place([moved.appending(path: "elixir.md")], unsortedName: "Unsorted")
        #expect(placements.map(\.projectID) == [project.id])
        #expect(relaunched.unsortedProject == nil)
    }

    @Test func aLooseFileRenamedInFinderIsListedOnce() throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/old.md")
        let library = library(scratch)
        library.place([page], unsortedName: "Unsorted")

        let renamed = page.deletingLastPathComponent().appending(path: "new.md")
        try FileManager.default.moveItem(at: page, to: renamed)
        let relaunched = self.library(scratch)
        let placements = relaunched.place([renamed], unsortedName: "Unsorted")

        #expect(placements.map(\.projectID) == [relaunched.unsortedProject?.id])
        #expect(relaunched.projects.count == 1)
        #expect(relaunched.unsortedProject?.looseFiles.count == 1)
    }

    @Test func aFileThatCantBeBookmarkedIsLeftOut() throws {
        let scratch = try Scratch()
        let library = library(scratch)
        let missing = scratch.url.appending(path: "gone.md")
        #expect(library.place([missing], unsortedName: "Unsorted").isEmpty)
        #expect(library.lastError != nil)
        // Unsorted is made the first time it is needed, not before.
        #expect(library.projects.isEmpty)
    }
}

@MainActor @Suite struct LooseFileWorkspaceTests {
    private func unsorted(_ scratch: Scratch, files: [URL]) -> (Workspace, ProjectLibrary) {
        let library = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
        library.place(files, unsortedName: "Unsorted")
        let id = library.unsortedProject!.id
        let workspace = Workspace(projectID: id, library: library)
        workspace.activate()
        return (workspace, library)
    }

    @Test func listsLooseFilesAndMarksMissingOnesUnavailable() throws {
        let scratch = try Scratch()
        let kept = try scratch.file("elsewhere/kept.md")
        let lost = try scratch.file("elsewhere/lost.md")
        let (workspace, library) = unsorted(scratch, files: [kept, lost])
        let id = workspace.projectID
        defer { workspace.deactivate() }
        #expect(workspace.looseFiles.map(\.status) == [.available, .available])

        try FileManager.default.removeItem(at: lost)
        workspace.refreshLooseFiles()
        #expect(workspace.looseFiles.map(\.status) == [.available, .unavailable])
        #expect(workspace.looseFiles.map(\.name) == ["kept.md", "lost.md"])
        #expect(workspace.looseFile(at: kept) != nil)

        // Removing the unavailable file leaves the rest of the project alone.
        workspace.removeLooseFile(workspace.looseFiles[1].id)
        #expect(workspace.looseFiles.map(\.name) == ["kept.md"])
        #expect(library.project(id)?.looseFiles.count == 1)
    }

    @Test func removingALooseFileLeavesItOnDisk() throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/page.md", "ink")
        let (workspace, _) = unsorted(scratch, files: [page])
        defer { workspace.deactivate() }

        workspace.removeLooseFile(workspace.looseFiles[0].id)
        #expect(workspace.looseFiles.isEmpty)
        #expect(try String(contentsOf: page, encoding: .utf8) == "ink")
    }

    @Test func aBookmarkThatNoLongerResolvesShowsAsUnavailableWithoutBreakingTheProject() throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/page.md")
        let (workspace, library) = unsorted(scratch, files: [page])
        let id = workspace.projectID
        library.update(id) { $0.looseFiles[0].bookmark = Data([0, 1, 2]) }
        workspace.deactivate()

        workspace.activate()
        defer { workspace.deactivate() }
        #expect(workspace.looseFiles.map(\.status) == [.unavailable])
        #expect(workspace.looseFiles[0].name == "page.md")
    }

    @Test func savingMakesABookmarkThatNoLongerResolvesAgain() throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/page.md", "one")
        let (workspace, library) = unsorted(scratch, files: [page])
        let id = workspace.projectID
        defer { workspace.deactivate() }
        library.update(id) { $0.looseFiles[0].bookmark = Data([0, 1, 2]) }
        workspace.sync()
        #expect(throws: (any Error).self) { try FolderBookmark.resolve(library.project(id)!.looseFiles[0].bookmark) }

        workspace.didSave(page)
        let resolved = try FolderBookmark.resolve(library.project(id)!.looseFiles[0].bookmark)
        #expect(resolved.url.resolvingSymlinksInPath() == page.resolvingSymlinksInPath())
    }

    @Test func aLooseFileStaysListedAndEditableAcrossSavesAndARelaunch() async throws {
        let scratch = try Scratch()
        let page = try scratch.file("elsewhere/page.md", "one")
        let (workspace, library) = unsorted(scratch, files: [page])
        let id = workspace.projectID
        let url = try #require(workspace.looseFiles[0].url)
        let document = try OpenDocument(url: url, autosaveDelay: .seconds(60))
        document.didSave = { [weak workspace] in workspace?.didSave($0) }
        for text in ["two", "three", "four"] {
            document.text = text
            document.save()
        }
        document.close()
        workspace.deactivate()

        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
        let again = Workspace(projectID: id, library: relaunched)
        again.activate()
        defer { again.deactivate() }
        #expect(again.looseFiles.map(\.status) == [.available])
        let reopened = try OpenDocument(url: try #require(again.looseFiles[0].url), autosaveDelay: .seconds(60))
        defer { reopened.close() }
        #expect(reopened.text == "four")
        #expect(library.project(id)?.looseFiles.count == 1)
    }
}

@Suite struct PendingOpensTests {
    private let first = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/a.md")])
    private let second = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/b.md")])

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
