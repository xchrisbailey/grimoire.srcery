import Foundation
import Observation

/// Every project the user has made, saved to a `ProjectStore` after each change.
@MainActor @Observable
public final class ProjectLibrary {
    public private(set) var projects: [Project]
    /// The last save or load failure, for the UI to surface.
    public var lastError: Error?
    /// A failed load blocks persistence until a successful retry, even if an alert is dismissed.
    public private(set) var loadError: Error?
    public var storageURL: URL { store.fileURL }

    private let store: ProjectStore

    public init(store: ProjectStore = .standard()) {
        self.store = store
        do {
            projects = try store.load()
        } catch {
            projects = []
            loadError = error
            lastError = error
        }
    }

    /// Reload after the user repairs the stored file or restores a compatible backup.
    public func retryLoad() {
        do {
            let loaded = try store.load()
            projects = loaded
            loadError = nil
            lastError = nil
        } catch {
            loadError = error
            lastError = error
        }
    }

    public func project(_ id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    @discardableResult
    public func createProject(named name: String, icon: String = "book.closed", kind: ProjectKind = .standard)
        throws -> Project
    {
        let project = Project(name: name, icon: icon, kind: kind)
        try commit(projects + [project])
        return project
    }

    public func deleteProject(_ id: Project.ID) throws {
        guard project(id) != nil else { throw LibraryError.unknownProject }
        guard project(id)?.pendingLifecycleOperations.isEmpty == true else { throw LifecycleError.pendingRepair }
        try commit(projects.filter { $0.id != id })
    }

    /// Publishes the changed snapshot only after its atomic save succeeds. Synchronous
    /// MainActor isolation keeps edits from separate windows from interleaving across I/O.
    public func update(_ id: Project.ID, _ change: (inout Project) -> Void) throws {
        try update(id, caseSensitiveNames: LifecyclePath.volumeCaseSensitiveNames, change)
    }

    func update(_ id: Project.ID, caseSensitiveNames: (URL) -> Bool?, _ change: (inout Project) -> Void) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { throw LibraryError.unknownProject }
        var candidate = projects
        change(&candidate[index])
        try validatePendingLifecycleEdits(
            from: projects[index], to: candidate[index], caseSensitiveNames: caseSensitiveNames)
        try commit(candidate)
    }

    /// Binds a folder the user picked to the project. Binding a folder that's already
    /// there returns the existing root.
    @discardableResult
    public func bindFolder(_ url: URL, to projectID: Project.ID) throws -> FolderRoot {
        guard let project = project(projectID) else { throw LibraryError.unknownProject }
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let existing = project.roots.first(where: { $0.lastKnownPath == path }) {
            return existing
        }
        let root = FolderRoot(
            name: url.lastPathComponent, bookmark: try FolderBookmark.make(for: url), lastKnownPath: path)
        try update(projectID) { $0.roots.append(root) }
        return root
    }

    public func unbindFolder(_ rootID: FolderRoot.ID, from projectID: Project.ID) throws {
        try requireRoot(rootID, in: projectID)
        try requireUnconfiguredRoot(rootID, in: projectID)
        try update(projectID) { project in
            project.roots.removeAll { $0.id == rootID }
            project.expandedFolders = project.expandedFolders.filter { $0.rootID != rootID }
            if project.lastOpenedFile?.rootID == rootID { project.lastOpenedFile = nil }
        }
    }

    /// Gives a root a name of the user's own. An empty alias clears it, so the folder's
    /// name shows again.
    public func setAlias(_ alias: String, of rootID: FolderRoot.ID, in projectID: Project.ID) throws {
        try requireRoot(rootID, in: projectID)
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        try update(projectID) { project in
            guard let index = project.roots.firstIndex(where: { $0.id == rootID }) else { return }
            project.roots[index].alias = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Stores a fresh bookmark for a root: after the user re-grants access, or when a
    /// stale bookmark was recreated.
    public func replaceBookmark(of rootID: FolderRoot.ID, in projectID: Project.ID, with url: URL) throws {
        try requireRoot(rootID, in: projectID)
        let bookmark = try FolderBookmark.make(for: url)
        try update(projectID) { project in
            guard let index = project.roots.firstIndex(where: { $0.id == rootID }) else { return }
            project.roots[index].bookmark = bookmark
            project.roots[index].name = url.lastPathComponent
            project.roots[index].lastKnownPath = url.standardizedFileURL.path(percentEncoded: false)
        }
    }

    private func requireRoot(_ rootID: FolderRoot.ID, in projectID: Project.ID) throws {
        guard let project = project(projectID) else { throw LibraryError.unknownProject }
        guard project.root(rootID) != nil else { throw LibraryError.unknownRoot }
    }

    /// Keeps the load guard and the single atomic-write/publication boundary shared by
    /// project edits and the first loose-file placement into a new Unsorted project.
    func commit(_ candidate: [Project]) throws {
        if let loadError {
            lastError = loadError
            throw loadError
        }
        do {
            try store.save(candidate)
            projects = candidate
            lastError = nil
        } catch {
            let failure = LibraryError.saveFailed(error)
            lastError = failure
            throw failure
        }
    }
}

public enum LibraryError: LocalizedError {
    case unknownProject
    case unknownRoot
    case unknownLooseFile
    case saveFailed(any Error)

    public var errorDescription: String? {
        switch self {
        case .unknownProject: String(localized: "That project no longer exists.")
        case .unknownRoot: String(localized: "That bound folder no longer exists in the project.")
        case .unknownLooseFile: String(localized: "That loose file no longer exists in the project.")
        case .saveFailed(let error):
            String(localized: "Project changes weren’t saved. Check access to the projects file and try again.")
                + "\n" + error.localizedDescription
        }
    }
}
