import Foundation

/// Where files opened from outside the app go: the project that already holds them, or
/// Unsorted.
extension ProjectLibrary {
    /// The files of one project that an open request put there, in the order they came.
    public struct Placement: Equatable, Sendable {
        public var projectID: Project.ID
        public var urls: [URL]

        public init(projectID: Project.ID, urls: [URL]) {
            self.projectID = projectID
            self.urls = urls
        }
    }

    /// Chooses a project for each of `urls`, grouped by project in the order each project
    /// first appears.
    ///
    /// A file under a folder of a project belongs to that project, and a file a project
    /// already lists as loose stays there. Any other file is added as a loose file to the
    /// Unsorted project, which is created, named `unsortedName`, when there is none.
    /// Folders and files are matched by resolving their bookmarks, not by the paths stored
    /// beside them, so a folder moved or a file renamed in Finder is still found. A file
    /// that can't be bookmarked is left out and reported in `lastError`.
    @discardableResult
    public func place(_ urls: [URL], unsortedName: String) -> [Placement] {
        var placements: [Placement] = []
        for url in urls {
            guard let id = projectID(for: url, unsortedName: unsortedName) else { continue }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            if let index = placements.firstIndex(where: { $0.projectID == id }) {
                if !placements[index].urls.contains(where: {
                    $0.standardizedFileURL.path(percentEncoded: false) == path
                }) {
                    placements[index].urls.append(url)
                }
            } else {
                placements.append(Placement(projectID: id, urls: [url]))
            }
        }
        return placements
    }

    /// The Unsorted project, if there is one.
    public var unsortedProject: Project? {
        projects.first { $0.kind == .unsorted }
    }

    /// Adds a file the user opened to a project's loose files. Adding one the project
    /// already lists returns the existing entry.
    @discardableResult
    public func addLooseFile(_ url: URL, to projectID: Project.ID) throws -> LooseFile {
        guard let project = project(projectID) else { throw LibraryError.unknownProject }
        if let existing = project.looseFiles.first(where: { Self.resolves($0, to: url) }) {
            return existing
        }
        let file = LooseFile(
            name: url.lastPathComponent, bookmark: try FolderBookmark.make(for: url),
            lastKnownPath: url.standardizedFileURL.path(percentEncoded: false))
        update(projectID) { $0.looseFiles.append(file) }
        return file
    }

    /// Takes a file off the project's list. Nothing on disk changes.
    public func removeLooseFile(_ fileID: LooseFile.ID, from projectID: Project.ID) {
        update(projectID) { project in
            project.looseFiles.removeAll { $0.id == fileID }
        }
    }

    /// Stores a fresh bookmark for a loose file: after the file was replaced by a save or
    /// moved, when the old bookmark still resolved but was stale.
    public func replaceBookmark(ofLooseFile fileID: LooseFile.ID, in projectID: Project.ID, with url: URL) throws {
        let bookmark = try FolderBookmark.make(for: url)
        update(projectID) { project in
            guard let index = project.looseFiles.firstIndex(where: { $0.id == fileID }) else { return }
            project.looseFiles[index].bookmark = bookmark
            project.looseFiles[index].name = url.lastPathComponent
            project.looseFiles[index].lastKnownPath = url.standardizedFileURL.path(percentEncoded: false)
        }
    }

    // MARK: - Private

    private func projectID(for url: URL, unsortedName: String) -> Project.ID? {
        if let id = projectHolding(folderOf: url) ?? projectListingLoosely(url) { return id }
        let projectID = unsortedProject?.id ?? createProject(named: unsortedName, icon: "tray", kind: .unsorted).id
        do {
            try addLooseFile(url, to: projectID)
            return projectID
        } catch {
            lastError = error
            return nil
        }
    }

    /// The project with the innermost root that contains `url`.
    private func projectHolding(folderOf url: URL) -> Project.ID? {
        var best: (id: Project.ID, depth: Int)?
        for project in projects {
            for root in project.roots {
                guard let rootURL = try? FolderBookmark.resolve(root.bookmark).url,
                    FileReference(rootID: root.id, rootURL: rootURL, url: url) != nil
                else { continue }
                let depth = rootURL.standardizedFileURL.pathComponents.count
                if best == nil || depth > best!.depth { best = (project.id, depth) }
            }
        }
        return best?.id
    }

    private func projectListingLoosely(_ url: URL) -> Project.ID? {
        projects.first { project in project.looseFiles.contains { Self.resolves($0, to: url) } }?.id
    }

    private static func resolves(_ file: LooseFile, to url: URL) -> Bool {
        guard let resolved = try? FolderBookmark.resolve(file.bookmark).url else { return false }
        return FileIdentity.same(resolved, url)
    }
}

/// Whether two URLs name the same file.
enum FileIdentity {
    static func same(_ first: URL, _ second: URL) -> Bool {
        if canonicalPath(first) == canonicalPath(second) { return true }
        guard let one = identifier(first), let other = identifier(second) else { return false }
        return one.isEqual(other)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    private static func identifier(_ url: URL) -> (any NSObjectProtocol)? {
        try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }
}
