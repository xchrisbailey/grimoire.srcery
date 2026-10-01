import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Projects and their files: the project switcher on top, one section per bound folder,
/// and "Bind a folder" at the foot.
struct SidebarView: View {
    @Environment(ProjectLibrary.self) private var library
    let workspace: Workspace?
    @Binding var selectedProjectID: Project.ID?
    @Binding var selectedFile: URL?

    @State private var actions = FileActions()

    var body: some View {
        VStack(spacing: 0) {
            ProjectSwitcher(selectedProjectID: $selectedProjectID)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if let workspace, let project = workspace.project {
                if project.roots.isEmpty {
                    emptyProject
                } else {
                    FileTreeView(workspace: workspace, selectedFile: $selectedFile, actions: actions)
                }
                footer(project)
            } else {
                Spacer()
            }
        }
        .background(Color.brand(\.sidebar))
        .fileActionPrompts(actions, workspace: workspace, selectedFile: $selectedFile)
    }

    private var emptyProject: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This grimoire is empty. Bind a folder to begin.")
                .brandFont(.chrome)
                .foregroundStyle(Color.brand(\.subtext))
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ project: Project) -> some View {
        HStack {
            Button {
                bindFolders(to: project.id)
            } label: {
                Label("Bind a folder", systemImage: "plus")
                    .brandFont(.chrome)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand(\.overlay1))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private func bindFolders(to projectID: Project.ID) {
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
}
