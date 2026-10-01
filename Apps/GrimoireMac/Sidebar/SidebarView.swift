import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Projects and their files: the project switcher on top, one section per bound folder,
/// and "Bind a folder" at the foot.
struct SidebarView: View {
    let window: WindowState

    var body: some View {
        VStack(spacing: 0) {
            ProjectSwitcher(window: window)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if let workspace = window.workspace, let project = workspace.project {
                if project.roots.isEmpty {
                    emptyProject
                } else {
                    FileTreeView(
                        workspace: workspace,
                        selectedFile: Binding(get: { window.selectedFile }, set: { window.select($0) }),
                        actions: window.actions)
                }
                footer
            } else {
                Spacer()
            }
        }
        .background(Color.brand(\.sidebar))
        .fileActionPrompts(window.actions, workspace: window.workspace)
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

    private var footer: some View {
        HStack {
            Button {
                window.bindFolders()
            } label: {
                Label("Bind a folder", systemImage: "plus")
                    .brandFont(.chrome)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand(\.overlay1))
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .accessibilityLabel(Text("Settings"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brand(\.overlay1))
            .help(Text("Settings"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}
