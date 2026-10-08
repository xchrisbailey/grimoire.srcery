import AppKit
import GrimoireCore

extension WindowState {
    func bringToFront() {
        hostWindow?.makeKeyAndOrderFront(nil)
    }

    /// Shows files that were opened from outside the app, ending on the last one. They
    /// belong to this window's project.
    func open(_ urls: [URL]) {
        guard let workspace, let url = urls.last else { return }
        workspace.sync()
        let file =
            workspace.reference(for: url).flatMap(workspace.url(for:)) ?? workspace.looseFile(at: url)?.url ?? url
        revealInTree(file)
        select(file)
    }

    /// Opens the folders that hold `url`, so its row shows.
    private func revealInTree(_ url: URL) {
        guard let workspace, var reference = workspace.reference(for: url) else { return }
        var folder = url.deletingLastPathComponent()
        while let parent = workspace.reference(for: folder), !parent.relativePath.isEmpty {
            workspace.setExpanded(folder, true)
            folder = folder.deletingLastPathComponent()
        }
        // Roots start expanded, so a root is opened by dropping its collapsed mark.
        reference.relativePath = ""
        if let root = workspace.url(for: reference) { workspace.setExpanded(root, false) }
    }

    // MARK: - Restoration

    /// `rootID/relative/path` for the selected file, for scene storage.
    var restorationFile: String {
        guard let selectedFile else { return "" }
        if let file = workspace?.looseFile(at: selectedFile) { return Self.loosePrefix + file.id.uuidString }
        guard let reference = workspace?.reference(for: selectedFile) else { return "" }
        return reference.rootID.uuidString + "/" + reference.relativePath
    }

    /// Marks a loose file in `restorationFile`, which has no root to start from.
    private static let loosePrefix = "loose/"

    /// Reopens the project and file a window last showed, unless files from Finder are
    /// waiting for this window.
    func restore(projectID storedProject: String, file storedFile: String, fallbackProject: String) {
        defer { ExternalOpens.shared.register(self) }
        let opens = ExternalOpens.shared
        if let waiting = opens.claim(preferring: UUID(uuidString: storedProject), isNew: storedProject.isEmpty),
            library.project(waiting.projectID) != nil
        {
            selectProject(waiting.projectID, openLastFile: false)
            open(waiting.urls)
            return
        }
        let ids = [storedProject, fallbackProject].compactMap(UUID.init(uuidString:))
        let id = ids.first { library.project($0) != nil } ?? library.projects.first?.id
        let reopens = Preferences.shared.restoresLastSession
        selectProject(id, openLastFile: reopens)
        guard reopens, !storedFile.isEmpty, let url = restorationURL(for: storedFile),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return }
        select(url)
    }

    private func restorationURL(for stored: String) -> URL? {
        if stored.hasPrefix(Self.loosePrefix) {
            guard let id = UUID(uuidString: String(stored.dropFirst(Self.loosePrefix.count))) else { return nil }
            return workspace?.looseFiles.first { $0.id == id }?.url
        }
        let parts = stored.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let rootID = UUID(uuidString: String(parts[0])) else { return nil }
        return workspace?.url(for: FileReference(rootID: rootID, relativePath: String(parts[1])))
    }
}
