import AppKit
import GrimoireCore
import GrimoireEditor
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
    /// The window's handle on its editor: find, outline, spells.
    let editor = EditorProxy()
    /// The open project's pages and their text, for Summon a page and Find in Project.
    private(set) var index = ProjectIndex()
    let search = ProjectSearch()
    /// The palette floating over the window, if one is open.
    var palette: Palette?
    private var preferences: Preferences { .shared }

    private(set) var projectID: Project.ID?
    private(set) var workspace: Workspace?
    private(set) var selectedFile: URL?
    private(set) var document: OpenDocument?
    /// Why the selected file couldn't be opened.
    var openError: Error?
    var projectPrompt: ProjectPrompt?
    var focusMode = false
    /// Preview or Raw for the open file. Each file remembers its own.
    var editorMode: EditorMode = .preview {
        didSet {
            if let selectedFile, editorMode != oldValue { FileModes.remember(editorMode, for: selectedFile) }
        }
    }
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

    /// Shows project `id`, reopening the file it last had open unless `openLastFile` is false.
    func selectProject(_ id: Project.ID?, openLastFile: Bool = true) {
        guard id != projectID else { return }
        closeDocument()
        workspace?.deactivate()
        projectID = id
        guard let id else {
            workspace = nil
            return
        }
        index = ProjectIndex()
        search.index = index
        search.end()
        let extensions = Set(preferences.fileExtensions(for: library.project(id)))
        let workspace = Workspace(projectID: id, library: library, scanner: FileScanner(extensions: extensions))
        workspace.activate()
        self.workspace = workspace
        if openLastFile, let reference = project?.lastOpenedFile, let url = workspace.url(for: reference) {
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
        editorMode = FileModes.mode(for: url, default: preferences.opensInRaw ? .raw : .preview)
        do {
            document = try OpenDocument(url: url, autosaveDelay: .seconds(preferences.autosaveDelay))
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

    /// Where images pasted into `url` are saved, when Settings puts them at the top of the
    /// bound folder. Nil keeps the editor's default, `assets/` next to the page.
    func imageFolder(for url: URL) -> URL? {
        guard preferences.imageLocation(for: project) == .projectFolder,
            let root = workspace?.folder(containing: url)?.url
        else { return nil }
        return root.appending(path: "assets", directoryHint: .isDirectory)
    }

    /// Settings changed which files are listed, or how long edits wait to save.
    func preferencesChanged() {
        workspace?.setExtensions(Set(preferences.fileExtensions(for: project)))
        document?.autosaveDelay = .seconds(preferences.autosaveDelay)
    }

    // MARK: - Search and palettes

    func showPalette(_ palette: Palette) {
        self.palette = self.palette == palette ? nil : palette
    }

    /// The trees changed: keep the index (and any search showing) current.
    func workspaceScanned() {
        guard let workspace else { return }
        index.update(from: workspace.folders)
        search.schedule(after: .zero)
    }

    /// Opens `url` and selects `range` in it, for a search result.
    func open(_ url: URL, revealing range: NSRange) {
        select(url)
        // The editor takes the new text on its next update.
        DispatchQueue.main.async { [editor] in
            DispatchQueue.main.async { editor.reveal(range) }
        }
    }

    /// Sends an action to the editor, as a menu item would.
    func sendToEditor(_ action: Selector) {
        DispatchQueue.main.async { [editor] in
            editor.focusEditor()
            NSApp.sendAction(action, to: nil, from: nil)
        }
    }

    /// Runs one of the Find menu's actions on the editor.
    func sendFindAction(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        DispatchQueue.main.async { [editor] in
            editor.focusEditor()
            NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
        }
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
        FileModes.remember(editorMode, for: newURL)
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
        let reopens = preferences.restoresLastSession
        selectProject(id, openLastFile: reopens)
        guard reopens, !storedFile.isEmpty else { return }
        let parts = storedFile.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let rootID = UUID(uuidString: String(parts[0])),
            let url = workspace?.url(for: FileReference(rootID: rootID, relativePath: String(parts[1]))),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }
        select(url)
    }
}

/// The mode each file was last shown in. Files not listed open in the default mode.
enum FileModes {
    private static let key = "grimoire.fileModes"
    /// Before files remembered Preview too, only Raw files were listed here.
    private static let legacyKey = "grimoire.rawFiles"
    /// Enough to cover the files anyone works in, without growing forever.
    private static let limit = 300

    static func mode(for url: URL, default fallback: EditorMode = .preview) -> EditorMode {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if let stored = entries.first(where: { $0.first == path }), stored.count == 2,
            let mode = EditorMode(rawValue: stored[1])
        {
            return mode
        }
        let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) ?? []
        return legacy.contains(path) ? .raw : fallback
    }

    static func remember(_ mode: EditorMode, for url: URL) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let rest = entries.filter { $0.first != path }
        UserDefaults.standard.set(Array(([[path, mode.rawValue]] + rest).prefix(limit)), forKey: key)
    }

    /// `[path, mode]` pairs, most recent first.
    private static var entries: [[String]] {
        UserDefaults.standard.array(forKey: key) as? [[String]] ?? []
    }
}

extension FocusedValues {
    /// The key window's state, for menu bar commands.
    @Entry var windowState: WindowState?
}
