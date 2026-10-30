import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct ProjectCommitTests {
    enum Edit: CaseIterable {
        case create, delete, settings, bind, unbind, alias, bookmark, addLoose, removeLoose, looseBookmark
    }

    @Test(arguments: Edit.allCases)
    func failedEditCanBeRetriedWithoutPublishingCandidate(edit: Edit) throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))
        let library = ProjectLibrary(store: store)
        let project = try library.createProject(named: "Notes")
        let folder = try scratch.folder("notes")
        let replacement = try scratch.folder("replacement")
        let root = try library.bindFolder(folder, to: project.id)
        let loose = try library.addLooseFile(scratch.file("loose.md"), to: project.id)
        let page = try scratch.file("another.md")
        try library.update(project.id) {
            $0.expandedFolders.insert(FileReference(rootID: root.id, relativePath: "drafts"))
            $0.lastOpenedFile = FileReference(rootID: root.id, relativePath: "draft.md")
        }
        let before = library.projects
        let bytes = try Data(contentsOf: store.fileURL)
        let apply: () throws -> Void = {
            switch edit {
            case .create: try library.createProject(named: "New")
            case .delete: try library.deleteProject(project.id)
            case .settings:
                try library.update(project.id) {
                    $0.overrides.fileExtensions = ["md", "txt"]
                    $0.dictionary = ["Grimoire"]
                }
            case .bind: try library.bindFolder(replacement, to: project.id)
            case .unbind: try library.unbindFolder(root.id, from: project.id)
            case .alias: try library.setAlias("Writing", of: root.id, in: project.id)
            case .bookmark: try library.replaceBookmark(of: root.id, in: project.id, with: replacement)
            case .addLoose: try library.addLooseFile(page, to: project.id)
            case .removeLoose: try library.removeLooseFile(loose.id, from: project.id)
            case .looseBookmark: try library.replaceBookmark(ofLooseFile: loose.id, in: project.id, with: page)
            }
        }

        try withBlockedWrites(to: store) { () throws in
            #expect(throws: (any Error).self) { try apply() }
            #expect(library.projects == before)
            #expect(try Data(contentsOf: store.fileURL) == bytes)
            #expect(ProjectLibrary(store: store).projects == before)
            #expect(library.lastError != nil)
        }

        try apply()
        #expect(library.projects != before)
        #expect(library.lastError == nil)
        #expect(ProjectLibrary(store: store).projects == library.projects)
    }

    @Test func failedSettingsWritePreservesVisibleAndStoredProject() throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))
        let library = ProjectLibrary(store: store)
        let project = try library.createProject(named: "Notes")
        let original = try Data(contentsOf: store.fileURL)

        try withBlockedWrites(to: store) { () throws in
            #expect(throws: (any Error).self) {
                try library.update(project.id) { $0.name = "Not saved" }
            }
            #expect(library.projects == [project])
            #expect(try Data(contentsOf: store.fileURL) == original)
            #expect(library.lastError != nil)
        }

        try library.update(project.id) { $0.name = "Saved" }
        #expect(library.lastError == nil)
        #expect(ProjectLibrary(store: store).projects.first?.name == "Saved")
    }

    @Test func externalOpenKeepsValidFilesAndReportsFailuresInEitherOrder() throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))
        let library = ProjectLibrary(store: store)
        let missing = scratch.url.appending(path: "missing.md")
        let first = try scratch.file("first.md")
        let second = try scratch.file("second.md")

        let placements = library.place([missing, first], unsortedName: "Unsorted")
        let unsorted = try #require(library.unsortedProject)
        #expect(placements == [.init(projectID: unsorted.id, urls: [first])])
        #expect(library.lastError != nil)
        #expect(ProjectLibrary(store: store).unsortedProject?.looseFiles.map(\.name) == ["first.md"])

        let next = library.place([second, missing], unsortedName: "Unsorted")
        #expect(next == [.init(projectID: unsorted.id, urls: [second])])
        #expect(library.lastError != nil)
        #expect(ProjectLibrary(store: store).unsortedProject?.looseFiles.map(\.name) == ["first.md", "second.md"])

        #expect(library.place([first], unsortedName: "Unsorted") == [.init(projectID: unsorted.id, urls: [first])])
        #expect(library.lastError == nil)
    }

    @Test func failedExternalPlacementNeverClaimsAnUncommittedProject() throws {
        let scratch = try Scratch()
        let store = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))
        let library = ProjectLibrary(store: store)
        let notes = try library.createProject(named: "Notes")
        let folder = try scratch.folder("notes")
        try library.bindFolder(folder, to: notes.id)
        let owned = try scratch.file("notes/owned.md")
        let loose = try scratch.file("loose.md")
        let before = library.projects
        let bytes = try Data(contentsOf: store.fileURL)

        try withBlockedWrites(to: store) { () throws in
            #expect(
                library.place([loose, owned], unsortedName: "Unsorted") == [.init(projectID: notes.id, urls: [owned])])
            #expect(library.projects == before)
            #expect(library.lastError != nil)
            #expect(try Data(contentsOf: store.fileURL) == bytes)
        }
        let placed = library.place([loose], unsortedName: "Unsorted")
        let unsorted = try #require(ProjectLibrary(store: store).unsortedProject)
        #expect(placed == [.init(projectID: unsorted.id, urls: [loose])])
        #expect(library.lastError == nil)

        let another = try scratch.file("another.md")
        let committed = library.projects
        try withBlockedWrites(to: store) {
            #expect(library.place([another], unsortedName: "Unsorted").isEmpty)
            #expect(library.projects == committed)
            #expect(library.lastError != nil)
        }
    }

    @Test func failedUnbindAndRegrantKeepBothWindowsOnTheCommittedRoot() async throws {
        let scratch = try Scratch()
        // Isolate storage permissions from the folders whose access must survive.
        let isolated = ProjectStore(fileURL: scratch.url.appending(path: "support/projects.json"))
        let shared = ProjectLibrary(store: isolated)
        let project = try shared.createProject(named: "Notes")
        let rootURL = try scratch.folder("notes")
        try scratch.file("notes/page.md", "ink")
        let root = try shared.bindFolder(rootURL, to: project.id)
        let windows = [
            Workspace(projectID: project.id, library: shared),
            Workspace(projectID: project.id, library: shared),
        ]
        for window in windows { window.activate() }
        defer { for window in windows { window.deactivate() } }
        let before = shared.projects
        let bytes = try Data(contentsOf: isolated.fileURL)
        let replacement = try scratch.folder("replacement")

        #expect(throws: (any Error).self) { try windows[0].unbind(UUID()) }
        #expect(throws: (any Error).self) { try windows[0].regrantAccess(to: UUID(), with: replacement) }
        #expect(windows[0].folders.first?.root == root)
        #expect(try Data(contentsOf: isolated.fileURL) == bytes)

        try withBlockedWrites(to: isolated) { () throws in
            #expect(throws: (any Error).self) { try windows[0].unbind(root.id) }
            #expect(throws: (any Error).self) { try windows[0].regrantAccess(to: root.id, with: replacement) }
            for window in windows {
                window.sync()
                #expect(window.folders.first?.url?.resolvingSymlinksInPath() == rootURL.resolvingSymlinksInPath())
                #expect(window.folders.first?.root == root)
            }
            #expect(shared.projects == before)
            #expect(try Data(contentsOf: isolated.fileURL) == bytes)
        }

        try scratch.file("notes/after-failure.md", "still accessible")
        for window in windows { window.refresh(root.id) }
        try await until { windows.allSatisfy { $0.folders.first?.tree?.documents.count == 2 } }
        try windows[0].setAlias("Writing", of: root.id)
        windows[1].sync()
        #expect(windows[1].folders.first?.root.displayName == "Writing")
        try windows[1].unbind(root.id)
        windows[0].sync()
        #expect(windows.allSatisfy { $0.folders.isEmpty })
        #expect(ProjectLibrary(store: isolated).projects.first?.roots.isEmpty == true)
        #expect(shared.lastError == nil)
        #expect(try String(contentsOf: rootURL.appending(path: "page.md"), encoding: .utf8) == "ink")
    }

    @Test func editsFromTwoWindowsComposeWithoutLostUpdates() async throws {
        let scratch = try Scratch()
        let (first, library) = try await scratch.workspace()
        let second = Workspace(projectID: first.projectID, library: library)
        second.activate()
        defer {
            first.deactivate()
            second.deactivate()
        }
        let root = try #require(first.folders.first?.id)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in try first.setAlias("Writing", of: root) }
            group.addTask { @MainActor in
                try library.update(second.projectID) { $0.overrides.intelligenceOff = true }
            }
            try await group.waitForAll()
        }
        first.sync()
        second.sync()
        let relaunched = ProjectLibrary(store: ProjectStore(fileURL: library.storageURL))
        #expect(relaunched.projects.first?.roots.first?.alias == "Writing")
        #expect(relaunched.projects.first?.overrides.intelligenceOff == true)
        #expect(first.project == second.project)
        #expect(first.project == relaunched.projects.first)
    }
}

/// Atomic replacement needs a writable parent even when the existing file is readable.
func withBlockedWrites(to store: ProjectStore, _ operation: () throws -> Void) throws {
    let directory = store.fileURL.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    defer {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            Issue.record(error)
        }
    }
    try operation()
}
