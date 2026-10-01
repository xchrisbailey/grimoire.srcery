import Foundation
import Observation

/// Every project the user has made, saved to a `ProjectStore` after each change.
@MainActor @Observable
public final class ProjectLibrary {
    public private(set) var projects: [Project]
    /// The last save or load failure, for the UI to surface.
    public var lastError: Error?

    private let store: ProjectStore

    public init(store: ProjectStore = .standard()) {
        self.store = store
        do {
            projects = try store.load()
        } catch {
            projects = []
            lastError = error
        }
    }

    public func project(_ id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    @discardableResult
    public func createProject(named name: String) -> Project {
        let project = Project(name: name)
        projects.append(project)
        save()
        return project
    }

    public func deleteProject(_ id: Project.ID) {
        projects.removeAll { $0.id == id }
        save()
    }

    /// Applies `change` to the project and saves. Does nothing for an unknown id.
    public func update(_ id: Project.ID, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[index])
        save()
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
        update(projectID) { $0.roots.append(root) }
        return root
    }

    public func unbindFolder(_ rootID: FolderRoot.ID, from projectID: Project.ID) {
        update(projectID) { project in
            project.roots.removeAll { $0.id == rootID }
            project.expandedFolders = project.expandedFolders.filter { $0.rootID != rootID }
            if project.lastOpenedFile?.rootID == rootID { project.lastOpenedFile = nil }
        }
    }

    /// Stores a fresh bookmark for a root: after the user re-grants access, or when a
    /// stale bookmark was recreated.
    public func replaceBookmark(of rootID: FolderRoot.ID, in projectID: Project.ID, with url: URL) throws {
        let bookmark = try FolderBookmark.make(for: url)
        update(projectID) { project in
            guard let index = project.roots.firstIndex(where: { $0.id == rootID }) else { return }
            project.roots[index].bookmark = bookmark
            project.roots[index].name = url.lastPathComponent
            project.roots[index].lastKnownPath = url.standardizedFileURL.path(percentEncoded: false)
        }
    }

    private func save() {
        do {
            try store.save(projects)
        } catch {
            lastError = error
        }
    }
}

public enum LibraryError: LocalizedError {
    case unknownProject

    public var errorDescription: String? {
        switch self {
        case .unknownProject: String(localized: "That project no longer exists.")
        }
    }
}
