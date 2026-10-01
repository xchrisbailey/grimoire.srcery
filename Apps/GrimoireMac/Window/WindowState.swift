import AppKit
import GrimoireCore
import SwiftUI

/// Everything one window shows: its project, the open workspace, the selected file and
/// the document being edited. One project per window, one document per window.
@MainActor @Observable
final class WindowState {
    enum ProjectPrompt: Equatable {
        case new
        case rename(Project.ID)
    }

    let library: ProjectLibrary
    let actions = FileActions()

    private(set) var projectID: Project.ID?
    private(set) var workspace: Workspace?
    private(set) var selectedFile: URL?
    private(set) var document: OpenDocument?
    /// Why the selected file couldn't be opened.
    var openError: Error?
    var projectPrompt: ProjectPrompt?
    var focusMode = false
    var columnVisibility: NavigationSplitViewVisibility = .all
    private var visibilityBeforeFocus: NavigationSplitViewVisibility = .all

    init(library: ProjectLibrary) {
        self.library = library
        actions.didCreate = { [weak self] url in self?.select(url) }
        actions.didMove = { [weak self] from, to in self?.itemMoved(from: from, to: to) }
        actions.didTrash = { [weak self] url in self?.itemTrashed(url) }
    }

    var project: Project? { projectID.flatMap(library.project) }

    // MARK: - Project

    func selectProject(_ id: Project.ID?) {
        guard id != projectID else { return }
        closeDocument()
        workspace?.deactivate()
        projectID = id
        guard let id else {
            workspace = nil
            return
        }
        let workspace = Workspace(projectID: id, library: library)
        workspace.activate()
        self.workspace = workspace
        if let reference = project?.lastOpenedFile, let url = workspace.url(for: reference) {
            select(url)
        }
    }

    /// The project's roots changed (bound or unbound elsewhere); update the workspace.
    func projectRootsChanged() {
        workspace?.sync()
        if let url = selectedFile, workspace?.reference(for: url) == nil { select(nil) }
    }

    func close() {
        closeDocument()
        workspace?.deactivate()
    }

    /// Lets the user pick folders to bind to this window's project.
    func bindFolders() {
        guard let projectID else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Bind")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                try library.bindFolder(url, to: projectID)
            } catch {
                actions.error = error
            }
        }
    }

    /// Focus mode shows only the editor: the sidebar and toolbar step away until esc.
    func setFocusMode(_ isOn: Bool) {
        guard isOn != focusMode else { return }
        focusMode = isOn
        if isOn {
            visibilityBeforeFocus = columnVisibility
            columnVisibility = .detailOnly
        } else {
            columnVisibility = visibilityBeforeFocus
        }
    }

    // MARK: - Document

    /// Opens `url` in this window, saving and closing whatever was open.
    func select(_ url: URL?) {
        guard url?.standardizedFileURL != selectedFile?.standardizedFileURL else { return }
        closeDocument()
        selectedFile = url
        guard let url else { return }
        do {
            document = try OpenDocument(url: url)
            openError = nil
            if let projectID, let reference = workspace?.reference(for: url) {
                library.update(projectID) { $0.lastOpenedFile = reference }
            }
        } catch {
            openError = error
        }
    }

    func save() {
        document?.save()
    }

    /// Opens a markdown file a link pointed at: in this window when it's inside the
    /// project, otherwise with the default app.
    func openLinkedFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            openError = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
            return
        }
        if workspace?.reference(for: url) != nil {
            select(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// The folder new files go in: the selected file's folder, else the first bound folder.
    var folderForNewFiles: URL? {
        if let selectedFile, workspace?.reference(for: selectedFile) != nil {
            return selectedFile.deletingLastPathComponent()
        }
        return workspace?.folders.first { $0.status == .available }?.url
    }

    func newFile() {
        guard let workspace, let folder = folderForNewFiles else { return }
        actions.createDocument(in: folder, workspace: workspace)
    }

    private func closeDocument() {
        document?.close()
        document = nil
        openError = nil
    }

    private func itemMoved(from: URL, to: URL) {
        guard let current = selectedFile else { return }
        let fromPath = from.standardizedFileURL.path(percentEncoded: false)
        let currentPath = current.standardizedFileURL.path(percentEncoded: false)
        let newURL: URL
        if currentPath == fromPath {
            newURL = to
        } else if currentPath.hasPrefix(fromPath.hasSuffix("/") ? fromPath : fromPath + "/") {
            let rest = currentPath.dropFirst(fromPath.count).trimmingPrefix("/")
            newURL = to.appending(path: String(rest))
        } else {
            return
        }
        selectedFile = newURL
        document?.moved(to: newURL)
        if let projectID, let reference = workspace?.reference(for: newURL) {
            library.update(projectID) { $0.lastOpenedFile = reference }
        }
    }

    private func itemTrashed(_ url: URL) {
        guard let current = selectedFile else { return }
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let currentPath = current.standardizedFileURL.path(percentEncoded: false)
        guard currentPath == path || currentPath.hasPrefix(path.hasSuffix("/") ? path : path + "/") else { return }
        document?.discard()
        document = nil
        selectedFile = nil
    }

    // MARK: - Restoration

    /// `rootID/relative/path` for the selected file, for scene storage.
    var restorationFile: String {
        guard let selectedFile, let reference = workspace?.reference(for: selectedFile) else { return "" }
        return reference.rootID.uuidString + "/" + reference.relativePath
    }

    /// Reopens the project and file a window last showed.
    func restore(projectID storedProject: String, file storedFile: String, fallbackProject: String) {
        let ids = [storedProject, fallbackProject].compactMap(UUID.init(uuidString:))
        let id = ids.first { library.project($0) != nil } ?? library.projects.first?.id
        selectProject(id)
        guard !storedFile.isEmpty else { return }
        let parts = storedFile.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let rootID = UUID(uuidString: String(parts[0])),
            let url = workspace?.url(for: FileReference(rootID: rootID, relativePath: String(parts[1]))),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }
        select(url)
    }
}

extension FocusedValues {
    /// The key window's state, for menu bar commands.
    @Entry var windowState: WindowState?
}
