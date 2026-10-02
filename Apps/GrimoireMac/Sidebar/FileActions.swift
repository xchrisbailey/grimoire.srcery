import GrimoireCore
import SwiftUI

/// Runs the tree's file operations and holds the prompts they need (rename, banish, errors).
@MainActor @Observable
final class FileActions {
    var renaming: URL?
    var newName = ""
    var banishing: URL?
    var error: Error?

    /// Called after a page is conjured, so the window can open it.
    @ObservationIgnored var didCreate: ((URL) -> Void)?
    /// Called after an item is renamed or moved, with its old and new URLs.
    @ObservationIgnored var didMove: ((URL, URL) -> Void)?
    /// Called after an item goes to the Trash.
    @ObservationIgnored var didTrash: ((URL) -> Void)?

    /// Conjures a page in `folder` and opens it, then offers to name it when `rename` is set.
    @discardableResult
    func createDocument(in folder: URL, workspace: Workspace, rename: Bool = true) -> URL? {
        var created: URL?
        perform(workspace, near: folder) {
            created = try FileOperations.createDocument(
                in: folder, named: FileNaming.name(from: Preferences.shared.newFileName))
        }
        guard let created else { return nil }
        workspace.setExpanded(folder, true)
        didCreate?(created)
        if rename { startRename(created) }
        return created
    }

    func createFolder(in folder: URL, workspace: Workspace) {
        perform(workspace, near: folder) {
            let url = try FileOperations.createFolder(in: folder)
            workspace.setExpanded(folder, true)
            startRename(url)
        }
    }

    func startRename(_ url: URL) {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        newName = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        renaming = url
    }

    func finishRename(workspace: Workspace) {
        guard let url = renaming else { return }
        renaming = nil
        perform(workspace, near: url) {
            let renamed = try FileOperations.rename(url, to: newName)
            if renamed != url { didMove?(url, renamed) }
        }
    }

    func banish(_ url: URL, workspace: Workspace) {
        perform(workspace, near: url) {
            try FileOperations.moveToTrash(url)
            didTrash?(url)
        }
    }

    /// Moves dropped items into `folder`. Only items inside this workspace are accepted.
    func move(_ urls: [URL], into folder: URL, workspace: Workspace) -> Bool {
        let inside = urls.filter { workspace.reference(for: $0) != nil }
        guard !inside.isEmpty else { return false }
        for url in inside {
            perform(workspace, near: url) {
                let moved = try FileOperations.move(url, into: folder)
                if moved != url { didMove?(url, moved) }
            }
        }
        workspace.refresh(of: folder)
        return true
    }

    func unbind(_ folder: BoundFolder, from workspace: Workspace) {
        workspace.unbind(folder.id)
    }

    private func perform(_ workspace: Workspace, near url: URL, _ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            self.error = error
        }
        workspace.refresh(of: url)
    }
}

extension Workspace {
    /// Rescans the root holding `url`.
    func refresh(of url: URL) {
        if let reference = reference(for: url) { refresh(reference.rootID) }
    }
}

extension View {
    /// The rename prompt, banish confirmation and error alert for a window's file actions.
    func fileActionPrompts(_ actions: FileActions, workspace: Workspace?) -> some View {
        modifier(FileActionPrompts(actions: actions, workspace: workspace))
    }
}

private struct FileActionPrompts: ViewModifier {
    @Bindable var actions: FileActions
    let workspace: Workspace?

    func body(content: Content) -> some View {
        content
            .alert(
                String(localized: "Rename “\(actions.renaming?.lastPathComponent ?? "")”"),
                isPresented: Binding(get: { actions.renaming != nil }, set: { if !$0 { actions.renaming = nil } })
            ) {
                TextField("Name", text: $actions.newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let workspace else { return }
                    actions.finishRename(workspace: workspace)
                }
            }
            .confirmationDialog(
                String(localized: "Banish \(actions.banishing?.lastPathComponent ?? "")?"),
                isPresented: Binding(get: { actions.banishing != nil }, set: { if !$0 { actions.banishing = nil } })
            ) {
                Button("Banish", role: .destructive) {
                    guard let workspace, let url = actions.banishing else { return }
                    actions.banish(url, workspace: workspace)
                }
            } message: {
                Text("It goes to the Trash.")
            }
            .alert(
                actions.error?.localizedDescription ?? "",
                isPresented: Binding(get: { actions.error != nil }, set: { if !$0 { actions.error = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
    }
}
