import Foundation
import Observation

/// One open project: its folders resolved from their bookmarks, their file trees, and
/// watchers that keep the trees current.
///
/// Call `activate()` when a window shows the project and `deactivate()` when it stops,
/// so folder access and watchers are only held while needed.
@MainActor @Observable
public final class Workspace {
    public let projectID: Project.ID
    public private(set) var folders: [BoundFolder] = []
    /// The project's loose files, resolved from their bookmarks.
    public private(set) var looseFiles: [BoundFile] = []
    public var lastError: Error?

    private let library: ProjectLibrary
    private var scanner: FileScanner
    private var accessed: [FolderRoot.ID: URL] = [:]
    private var accessedFiles: [LooseFile.ID: URL] = [:]
    private var watchers: [FolderRoot.ID: FolderWatcher] = [:]
    private var scans: [FolderRoot.ID: Task<Void, Never>] = [:]
    public private(set) var isActive = false
    /// Counts finished scans, so observers (the search index) can follow file changes even
    /// when a tree's shape stays the same.
    public private(set) var scanCount = 0

    public init(projectID: Project.ID, library: ProjectLibrary, scanner: FileScanner = FileScanner()) {
        self.projectID = projectID
        self.library = library
        self.scanner = scanner
    }

    public var project: Project? { library.project(projectID) }

    /// Resolves every root, starts watching, and scans. Calling it again picks up roots
    /// bound since the last call.
    public func activate() {
        isActive = true
        sync()
    }

    /// Stops watchers and gives up folder access.
    public func deactivate() {
        isActive = false
        for id in Array(accessed.keys) { release(id) }
        for id in Array(accessedFiles.keys) { releaseFile(id) }
        folders = []
        looseFiles = []
    }

    /// Brings `folders` and `looseFiles` in line with the project: opens new ones, releases
    /// removed ones.
    public func sync() {
        guard isActive, let project else { return }
        let ids = Set(project.roots.map(\.id))
        for id in Array(accessed.keys) where !ids.contains(id) { release(id) }
        folders = project.roots.map { root in
            if var existing = folders.first(where: { $0.id == root.id }), existing.status != .needsAccess {
                existing.root = root
                return existing
            }
            return open(root)
        }
        syncLooseFiles(project)
    }

    /// Resolves every loose file again, to pick up one that came back or went missing.
    public func refreshLooseFiles() {
        guard isActive, let project else { return }
        for id in Array(accessedFiles.keys) { releaseFile(id) }
        looseFiles = project.looseFiles.map(openFile)
    }

    /// The loose file at `url`, if the project lists it and it's available.
    public func looseFile(at url: URL) -> BoundFile? {
        looseFiles.first { file in file.url.map { FileIdentity.same($0, url) } ?? false }
    }

    /// Takes a loose file off the project's list. Nothing on disk changes.
    public func removeLooseFile(_ fileID: LooseFile.ID) {
        library.removeLooseFile(fileID, from: projectID)
        sync()
    }

    /// The file at `url` was just written. Saving atomically replaces the file, so a loose
    /// file's bookmark is made again while it no longer resolves exactly.
    public func didSave(_ url: URL) {
        guard let bound = looseFile(at: url) else { return }
        if let resolved = try? FolderBookmark.resolve(bound.file.bookmark),
            !resolved.isStale, FileIdentity.same(resolved.url, url)
        {
            return
        }
        do {
            try library.replaceBookmark(ofLooseFile: bound.id, in: projectID, with: url)
        } catch {
            lastError = error
            return
        }
        if let file = project?.looseFiles.first(where: { $0.id == bound.id }),
            let index = looseFiles.firstIndex(where: { $0.id == bound.id })
        {
            looseFiles[index].file = file
        }
    }

    /// Rescans one folder now, for example after a file operation.
    public func refresh(_ rootID: FolderRoot.ID) {
        guard let url = folders.first(where: { $0.id == rootID })?.url else { return }
        scans[rootID]?.cancel()
        let scanner = scanner
        scans[rootID] = Task { [weak self] in
            let tree = await Task.detached(priority: .userInitiated) { scanner.scan(url) }.value
            guard !Task.isCancelled, let self, let index = self.folders.firstIndex(where: { $0.id == rootID })
            else { return }
            self.folders[index].tree = tree
            self.folders[index].status = .available
            self.scanCount += 1
        }
    }

    public func refreshAll() {
        for folder in folders { refresh(folder.id) }
    }

    /// The file extensions the trees list. Changing them rescans every folder.
    public var extensions: Set<String> { scanner.extensions }

    public func setExtensions(_ extensions: Set<String>) {
        guard extensions != scanner.extensions else { return }
        scanner.extensions = extensions
        refreshAll()
    }

    /// Changes the sort order or whether hidden files show, and rescans.
    public func setListing(_ listing: FileListing) {
        guard listing != scanner.listing else { return }
        scanner.listing = listing
        refreshAll()
    }

    /// Stores access to a folder the user picked again after its bookmark stopped working.
    public func regrantAccess(to rootID: FolderRoot.ID, with url: URL) {
        do {
            try library.replaceBookmark(of: rootID, in: projectID, with: url)
            release(rootID)
            if let index = folders.firstIndex(where: { $0.id == rootID }), let root = project?.root(rootID) {
                folders[index] = open(root)
            }
        } catch {
            lastError = error
        }
    }

    /// Removes a folder from the project. Nothing on disk changes.
    public func unbind(_ rootID: FolderRoot.ID) {
        library.unbindFolder(rootID, from: projectID)
        sync()
    }

    /// Shows the folder under `alias` instead of its name. Empty clears it.
    public func setAlias(_ alias: String, of rootID: FolderRoot.ID) {
        library.setAlias(alias, of: rootID, in: projectID)
        sync()
    }

    // MARK: - Paths

    /// The folder containing `url`, if it's inside one of this workspace's roots.
    public func folder(containing url: URL) -> BoundFolder? {
        folders.first { folder in
            guard let root = folder.url else { return false }
            return FileReference(rootID: folder.id, rootURL: root, url: url) != nil
        }
    }

    public func reference(for url: URL) -> FileReference? {
        for folder in folders {
            guard let root = folder.url else { continue }
            if let reference = FileReference(rootID: folder.id, rootURL: root, url: url) { return reference }
        }
        return nil
    }

    public func url(for reference: FileReference) -> URL? {
        folders.first { $0.id == reference.rootID }?.url.map(reference.url(in:))
    }

    // MARK: - Tree state

    public func isExpanded(_ url: URL) -> Bool {
        guard let reference = reference(for: url) else { return false }
        return project?.expandedFolders.contains(reference) ?? false
    }

    public func setExpanded(_ url: URL, _ expanded: Bool) {
        guard let reference = reference(for: url), isExpanded(url) != expanded else { return }
        library.update(projectID) { project in
            if expanded {
                project.expandedFolders.insert(reference)
            } else {
                project.expandedFolders.remove(reference)
            }
        }
    }

    // MARK: - Access

    private func open(_ root: FolderRoot) -> BoundFolder {
        var folder = BoundFolder(root: root, status: .needsAccess)
        guard let resolved = try? FolderBookmark.resolve(root.bookmark) else { return folder }
        let url = resolved.url
        let accessing = url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            if accessing { url.stopAccessingSecurityScopedResource() }
            return folder
        }
        if accessing { accessed[root.id] = url }
        if resolved.isStale {
            try? library.replaceBookmark(of: root.id, in: projectID, with: url)
            folder.root = project?.root(root.id) ?? root
        }
        folder.url = url
        folder.status = .loading
        let id = root.id
        watchers[id] = FolderWatcher(url: url) { [weak self] _ in
            Task { @MainActor in self?.refresh(id) }
        }
        // `folders` may not hold this folder yet; scan once it's in place.
        Task { [weak self] in self?.refresh(id) }
        return folder
    }

    private func syncLooseFiles(_ project: Project) {
        let ids = Set(project.looseFiles.map(\.id))
        for id in Array(accessedFiles.keys) where !ids.contains(id) { releaseFile(id) }
        looseFiles = project.looseFiles.map { file in
            if var existing = looseFiles.first(where: { $0.id == file.id }), existing.status == .available {
                existing.file = file
                return existing
            }
            return openFile(file)
        }
    }

    private func openFile(_ file: LooseFile) -> BoundFile {
        var bound = BoundFile(file: file, status: .unavailable)
        guard let resolved = try? FolderBookmark.resolve(file.bookmark) else { return bound }
        let url = resolved.url
        let accessing = url.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            if accessing { url.stopAccessingSecurityScopedResource() }
            return bound
        }
        if accessing { accessedFiles[file.id] = url }
        if resolved.isStale {
            do {
                try library.replaceBookmark(ofLooseFile: file.id, in: projectID, with: url)
            } catch {
                lastError = error
            }
            bound.file = project?.looseFiles.first { $0.id == file.id } ?? file
        }
        bound.url = url
        bound.status = .available
        return bound
    }

    private func releaseFile(_ fileID: LooseFile.ID) {
        accessedFiles.removeValue(forKey: fileID)?.stopAccessingSecurityScopedResource()
    }

    private func release(_ rootID: FolderRoot.ID) {
        scans.removeValue(forKey: rootID)?.cancel()
        watchers.removeValue(forKey: rootID)?.stop()
        accessed.removeValue(forKey: rootID)?.stopAccessingSecurityScopedResource()
    }
}

/// A bound folder as this workspace sees it.
public struct BoundFolder: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case loading
        case available
        /// The bookmark no longer resolves, or the folder is gone. The user needs to
        /// pick it again (`regrantAccess`).
        case needsAccess
    }

    public var root: FolderRoot
    public var status: Status
    /// Where the bookmark resolved to.
    public var url: URL?
    public var tree: FileNode?

    public var id: FolderRoot.ID { root.id }
}

/// A loose file as this workspace sees it.
public struct BoundFile: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case available
        /// The bookmark no longer resolves, or the file is gone. It can only be removed
        /// from the list.
        case unavailable
    }

    public var file: LooseFile
    public var status: Status
    /// Where the bookmark resolved to.
    public var url: URL?

    public var id: LooseFile.ID { file.id }
    /// The file's name, from where it resolved or where it was last seen.
    public var name: String { url?.lastPathComponent ?? file.name }
}
