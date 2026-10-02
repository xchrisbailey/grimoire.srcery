import Foundation
import Testing

@testable import GrimoireCore

/// A fresh folder under the temporary directory, removed when the value is.
final class Scratch {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "grimoire-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ path: String, _ contents: String = "") throws -> URL {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

@Suite struct ProjectStoreTests {
    @Test func savesAndLoadsProjects() throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "nested/projects.json"))
        #expect(try store.load().isEmpty)

        let rootID = UUID()
        let project = Project(
            name: "Potions", color: .sparkle,
            roots: [FolderRoot(id: rootID, name: "notes", bookmark: Data([1, 2, 3]), lastKnownPath: "/tmp/notes")],
            lastOpenedFile: FileReference(rootID: rootID, relativePath: "brews/elixir.md"),
            expandedFolders: [FileReference(rootID: rootID, relativePath: "brews")])
        try store.save([project])
        #expect(try store.load() == [project])
    }

    @Test func fileReferencesAreRelativeToTheirRoot() {
        let root = URL(filePath: "/Users/me/notes", directoryHint: .isDirectory)
        let id = UUID()
        let reference = FileReference(rootID: id, rootURL: root, url: root.appending(path: "a/b.md"))
        #expect(reference?.relativePath == "a/b.md")
        #expect(reference?.url(in: root).path() == "/Users/me/notes/a/b.md")
        #expect(FileReference(rootID: id, rootURL: root, url: root)?.relativePath == "")
        #expect(FileReference(rootID: id, rootURL: root, url: URL(filePath: "/Users/me/notes-2/c.md")) == nil)
    }
}

@Suite struct FileScannerTests {
    @Test func listsOnlyDocumentsAndSkipsNoise() throws {
        let scratch = try Scratch()
        try scratch.file("README.md")
        try scratch.file("guide.mdx")
        try scratch.file("photo.png")
        try scratch.file(".hidden.md")
        try scratch.file("node_modules/pkg/readme.md")
        try scratch.file(".git/notes.md")
        try scratch.file("src/main.swift")
        try scratch.file("docs/intro.md")
        try scratch.file("docs/Chapter 10.md")
        try scratch.file("docs/Chapter 2.md")
        try scratch.folder("drafts")

        let tree = FileScanner().scan(scratch.url)
        #expect(tree.isFolder)
        #expect(tree.children?.map(\.name) == ["docs", "drafts", "guide.mdx", "README.md"])
        let docs = try #require(tree.children?.first)
        #expect(docs.children?.map(\.name) == ["Chapter 2.md", "Chapter 10.md", "intro.md"])
        #expect(tree.documents.count == 5)
        #expect(tree.children?.last?.children == nil)
    }

    @Test func sortsByDateAndShowsHiddenFiles() throws {
        let scratch = try Scratch()
        let older = try scratch.file("alpha.md")
        let newer = try scratch.file("beta.md")
        try scratch.file(".secret.md")
        try scratch.folder("zeta")
        try scratch.file("zeta/inside.md")
        let now = Date()
        let files = FileManager.default
        try files.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: older.path)
        try files.setAttributes([.modificationDate: now], ofItemAtPath: newer.path)

        let byDate = FileScanner(listing: FileListing(sort: .modified)).scan(scratch.url)
        #expect(byDate.children?.map(\.name) == ["zeta", "beta.md", "alpha.md"])
        let mixed = FileScanner(listing: FileListing(sort: .name, foldersFirst: false)).scan(scratch.url)
        #expect(mixed.children?.map(\.name) == ["alpha.md", "beta.md", "zeta"])
        let hidden = FileScanner(listing: FileListing(showsHiddenFiles: true)).scan(scratch.url)
        #expect(hidden.children?.map(\.name).contains(".secret.md") == true)
    }

    @Test func namesNewFilesFromATemplate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_790_930_000)
        #expect(FileNaming.name(from: "{date} Notes", date: date, calendar: calendar) == "2026-10-02 Notes")
        #expect(FileNaming.name(from: "Log {time}", date: date, calendar: calendar).hasPrefix("Log "))
        #expect(FileNaming.name(from: "  ", date: date) == "Untitled")
        #expect(FileNaming.name(from: "a/b", date: date) == "a-b")
        #expect(FileNaming.name(from: ".hidden", date: date) == "hidden")
        #expect(FileNaming.folderComponents("notes/../inbox/") == ["notes", "inbox"])
    }

    @Test func extensionsAreConfigurable() throws {
        let scratch = try Scratch()
        try scratch.file("a.md")
        try scratch.file("b.txt")
        let tree = FileScanner(extensions: ["txt"]).scan(scratch.url)
        #expect(tree.documents.map(\.name) == ["b.txt"])
    }
}

@Suite struct FileOperationsTests {
    @Test func createsUniquelyNamedItems() throws {
        let scratch = try Scratch()
        let first = try FileOperations.createDocument(in: scratch.url)
        let second = try FileOperations.createDocument(in: scratch.url)
        #expect(first.lastPathComponent == "Untitled.md")
        #expect(second.lastPathComponent == "Untitled 2.md")
        let folder = try FileOperations.createFolder(in: scratch.url)
        #expect(folder.lastPathComponent == "New Folder")
    }

    @Test func renameKeepsTheExtension() throws {
        let scratch = try Scratch()
        let file = try scratch.file("draft.md", "# Draft")
        let renamed = try FileOperations.rename(file, to: "potions")
        #expect(renamed.lastPathComponent == "potions.md")
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "# Draft")
        let mdx = try FileOperations.rename(renamed, to: "potions.mdx")
        #expect(mdx.lastPathComponent == "potions.mdx")

        try scratch.file("taken.md")
        #expect(throws: FileOperationError.alreadyExists("taken.md")) { try FileOperations.rename(mdx, to: "taken.md") }
        #expect(throws: FileOperationError.invalidName("a/b")) { try FileOperations.rename(mdx, to: "a/b") }

        let folder = try scratch.folder("old.notes")
        #expect(try FileOperations.rename(folder, to: "new").lastPathComponent == "new")
    }

    @Test func movesIntoFolders() throws {
        let scratch = try Scratch()
        let file = try scratch.file("loose.md")
        let folder = try scratch.folder("shelf")
        let moved = try FileOperations.move(file, into: folder)
        #expect(moved.path() == folder.appending(path: "loose.md").path())
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
        #expect(throws: FileOperationError.cannotMoveIntoItself("shelf")) {
            try FileOperations.move(folder, into: folder.appending(path: "inner"))
        }
    }

    @Test func movesToTheTrash() throws {
        let scratch = try Scratch()
        let file = try scratch.file("banished.md")
        let trashed = try FileOperations.moveToTrash(file)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        if let trashed { try? FileManager.default.removeItem(at: trashed) }
    }
}

@Suite struct ExternalChangeTests {
    @Test func reloadsWhenThereAreNoLocalChanges() {
        #expect(ExternalChange.resolve(saved: "a", local: "a", disk: "b") == .reload("b"))
    }

    @Test func ignoresItsOwnWrites() {
        #expect(ExternalChange.resolve(saved: "a", local: "a", disk: "a") == .none)
        #expect(ExternalChange.resolve(saved: "a", local: "b", disk: "a") == .none)
        #expect(ExternalChange.resolve(saved: "a", local: "b", disk: "b") == .none)
    }

    @Test func conflictsWhenBothSidesChanged() {
        #expect(ExternalChange.resolve(saved: "a", local: "b", disk: "c") == .conflict(disk: "c"))
    }
}

@Suite struct FolderWatcherTests {
    @Test func seesFilesCreatedOutsideTheApp() async throws {
        let scratch = try Scratch()
        let (events, continuation) = AsyncStream<[String]>.makeStream()
        let watcher = FolderWatcher(url: scratch.url, latency: 0.05) { continuation.yield($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        try scratch.file("new.md")
        let saw = await firstEvent(in: events, matching: { $0.contains { $0.hasSuffix("new.md") } })
        #expect(saw)
    }
}

/// Waits up to `timeout` for an element matching `predicate`.
func firstEvent<T: Sendable>(
    in stream: AsyncStream<T>, timeout: Duration = .seconds(5), matching predicate: @escaping @Sendable (T) -> Bool
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await value in stream where predicate(value) { return true }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}

@MainActor @Suite struct WorkspaceTests {
    /// The "done when" for #4: make a project, bind two unrelated folders, see both trees,
    /// relaunch (a new library over the same store) and still have access; a file made
    /// outside the app appears without a manual refresh.
    @Test func bindsFoldersAndSurvivesRelaunch() async throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("one/notes")
        let blog = try scratch.folder("elsewhere/blog")
        try scratch.file("one/notes/spells.md")
        try scratch.file("elsewhere/blog/post.mdx")
        let store = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))

        let library = ProjectLibrary(store: store)
        let project = library.createProject(named: "Grimoire")
        try library.bindFolder(notes, to: project.id)
        try library.bindFolder(blog, to: project.id)
        try library.bindFolder(notes, to: project.id)
        #expect(library.project(project.id)?.roots.count == 2)

        let relaunched = ProjectLibrary(store: store)
        #expect(relaunched.projects.map(\.name) == ["Grimoire"])
        let workspace = Workspace(projectID: project.id, library: relaunched)
        workspace.activate()
        defer { workspace.deactivate() }

        try await until { workspace.folders.allSatisfy { $0.status == .available } }
        #expect(workspace.folders.map(\.root.name) == ["notes", "blog"])
        #expect(workspace.folders.compactMap(\.tree).flatMap(\.documents).map(\.name) == ["spells.md", "post.mdx"])

        try await Task.sleep(for: .milliseconds(300))
        try scratch.file("one/notes/new spell.md")
        try await until {
            workspace.folders.first?.tree?.documents.map(\.name) == ["new spell.md", "spells.md"]
        }
    }

    @Test func aliasesFolders() throws {
        let scratch = try Scratch()
        let content = try scratch.folder("somewhere/content")
        let store = ProjectStore(fileURL: scratch.url.appending(path: "projects.json"))
        let library = ProjectLibrary(store: store)
        let project = library.createProject(named: "Site")
        let root = try library.bindFolder(content, to: project.id)
        #expect(root.displayName == "content")

        library.setAlias("  srcery.computer ", of: root.id, in: project.id)
        #expect(ProjectLibrary(store: store).project(project.id)?.roots.first?.displayName == "srcery.computer")

        library.setAlias(" ", of: root.id, in: project.id)
        #expect(library.project(project.id)?.roots.first?.alias == nil)
        #expect(library.project(project.id)?.roots.first?.displayName == "content")
    }

    @Test func remembersExpandedFolders() async throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("notes")
        let shelf = try scratch.file("notes/shelf/book.md").deletingLastPathComponent()
        let library = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
        let project = library.createProject(named: "Library")
        try library.bindFolder(notes, to: project.id)
        let workspace = Workspace(projectID: project.id, library: library)
        workspace.activate()
        defer { workspace.deactivate() }

        #expect(!workspace.isExpanded(shelf))
        workspace.setExpanded(shelf, true)
        #expect(workspace.isExpanded(shelf))
        #expect(library.project(project.id)?.expandedFolders.map(\.relativePath) == ["shelf"])
    }

    @Test func flagsFoldersThatNeedAccessAgain() async throws {
        let scratch = try Scratch()
        let gone = try scratch.folder("gone")
        let library = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
        let project = library.createProject(named: "Lost")
        try library.bindFolder(gone, to: project.id)
        try FileManager.default.removeItem(at: gone)

        let workspace = Workspace(projectID: project.id, library: library)
        workspace.activate()
        defer { workspace.deactivate() }
        #expect(workspace.folders.first?.status == .needsAccess)

        let found = try scratch.folder("found")
        try scratch.file("found/page.md")
        workspace.regrantAccess(to: workspace.folders[0].id, with: found)
        try await until { workspace.folders.first?.status == .available }
        #expect(library.project(project.id)?.roots.first?.name == "found")
    }
}
