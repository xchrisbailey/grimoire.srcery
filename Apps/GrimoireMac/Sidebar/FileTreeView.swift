import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The project's files: one collapsible section per bound folder, with only `.md` and
/// `.mdx` files listed.
struct FileTreeView: View {
    let workspace: Workspace
    @Binding var selectedFile: URL?
    let actions: FileActions

    var body: some View {
        List(selection: $selectedFile) {
            ForEach(workspace.folders) { folder in
                Section(isExpanded: expansion(of: folder)) {
                    switch folder.status {
                    case .available, .loading:
                        if let tree = folder.tree {
                            FileNodeRows(node: tree, workspace: workspace, actions: actions)
                        }
                    case .needsAccess:
                        needsAccess(folder)
                    }
                } header: {
                    RootHeader(folder: folder, workspace: workspace, actions: actions)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func expansion(of folder: BoundFolder) -> Binding<Bool> {
        // Roots start expanded, so a stored reference marks a collapsed root.
        let reference = FileReference(rootID: folder.id, relativePath: "")
        return Binding(
            get: { !(workspace.project?.expandedFolders.contains(reference) ?? false) },
            set: { expanded in
                guard let url = folder.url else { return }
                workspace.setExpanded(url, !expanded)
            })
    }

    private func needsAccess(_ folder: BoundFolder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Grimoire can't open this folder anymore. It may have moved, or access needs to be granted again.")
                .brandFont(.chrome)
                .foregroundStyle(Color.brand(\.subtext))
                .fixedSize(horizontal: false, vertical: true)
            Button("Grant Access…") { regrant(folder) }
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func regrant(_ folder: BoundFolder) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder.root.lastKnownURL.deletingLastPathComponent()
        panel.message = String(localized: "Choose “\(folder.root.name)” to keep using it in this project.")
        panel.prompt = String(localized: "Grant Access")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.regrantAccess(to: folder.id, with: url)
    }
}

/// A bound folder's section header: its name and where it lives.
private struct RootHeader: View {
    let folder: BoundFolder
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        HStack(spacing: 6) {
            Text(folder.root.name)
                .brandFont(.chrome)
                .foregroundStyle(Color.brand(\.subtext))
            if folder.status == .needsAccess {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.brand(\.callout))
                    .help(Text("Needs access"))
            }
            Spacer(minLength: 4)
            Text(abbreviatedParent)
                .brandFont(.metadata)
                .foregroundStyle(Color.brand(\.overlay0))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .contentShape(.rect)
        .contextMenu {
            if let url = folder.url {
                FolderMenu(url: url, workspace: workspace, actions: actions)
                Divider()
            }
            Button("Unbind Folder") { actions.unbind(folder, from: workspace) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = folder.url else { return false }
            return actions.move(urls, into: url, workspace: workspace)
        }
    }

    private var abbreviatedParent: String {
        let parent = (folder.url ?? folder.root.lastKnownURL).deletingLastPathComponent().path(percentEncoded: false)
        let home = Self.userHome
        let trimmed = parent.hasSuffix("/") && parent.count > 1 ? String(parent.dropLast()) : parent
        if trimmed == home { return "~" }
        if trimmed.hasPrefix(home + "/") { return "~" + trimmed.dropFirst(home.count) }
        return trimmed
    }

    /// The real home folder; inside the sandbox `NSHomeDirectory()` is the container.
    private static let userHome: String = {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }()
}

/// The rows under a folder: subfolders as disclosure groups, then documents.
private struct FileNodeRows: View {
    let node: FileNode
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        ForEach(node.children ?? []) { child in
            if child.isFolder {
                DisclosureGroup(isExpanded: expansion(of: child)) {
                    FileNodeRows(node: child, workspace: workspace, actions: actions)
                } label: {
                    FolderRow(node: child, workspace: workspace, actions: actions)
                }
            } else {
                DocumentRow(node: child, workspace: workspace, actions: actions)
                    .tag(child.url)
            }
        }
    }

    private func expansion(of folder: FileNode) -> Binding<Bool> {
        Binding(
            get: { workspace.isExpanded(folder.url) },
            set: { workspace.setExpanded(folder.url, $0) })
    }
}

private struct FolderRow: View {
    let node: FileNode
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        Label {
            Text(node.name).brandFont(.chrome)
        } icon: {
            Image(systemName: "folder")
        }
        .foregroundStyle(Color.brand(\.subtext))
        .draggable(node.url)
        .dropDestination(for: URL.self) { urls, _ in
            return actions.move(urls, into: node.url, workspace: workspace)
        }
        .contextMenu {
            FolderMenu(url: node.url, workspace: workspace, actions: actions)
            Divider()
            ItemMenu(url: node.url, isFolder: true, workspace: workspace, actions: actions)
        }
    }
}

private struct DocumentRow: View {
    let node: FileNode
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(node.url.deletingPathExtension().lastPathComponent)
                    .brandFont(.chrome)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.brand(\.overlay1))
            }
            Spacer(minLength: 4)
            Text(node.url.pathExtension.lowercased())
                .brandFont(.metadata)
                .foregroundStyle(Color.brand(\.overlay0))
        }
        .draggable(node.url)
        .contextMenu {
            ItemMenu(url: node.url, isFolder: false, workspace: workspace, actions: actions)
        }
    }
}

/// Commands for anything inside a folder: make a page or a folder in it.
private struct FolderMenu: View {
    let url: URL
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        Button("Conjure a page") { actions.createDocument(in: url, workspace: workspace) }
        Button("New Folder") { actions.createFolder(in: url, workspace: workspace) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// Commands for a file or subfolder: rename, reveal, banish.
private struct ItemMenu: View {
    let url: URL
    let isFolder: Bool
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        Button("Rename…") { actions.startRename(url) }
        if !isFolder {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Divider()
        Button("Banish…", role: .destructive) { actions.banishing = url }
    }
}
