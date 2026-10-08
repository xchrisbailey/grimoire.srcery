import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
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
                if !project.roots.isEmpty, !window.search.isActive, !window.ask.isActive { summonField }
                if project.roots.isEmpty && project.looseFiles.isEmpty {
                    emptyProject(of: project)
                } else if window.search.isActive {
                    SearchResultsView(window: window)
                } else if window.ask.isActive {
                    AskView(window: window)
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

    /// Looks like a search field, as in the brand mockup; opens Summon a page.
    private var summonField: some View {
        Button {
            window.showPalette(.summon)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Summon a page")
                Spacer()
                Text(verbatim: "⌘P").font(.brand(.metadata))
            }
            .font(.brand(.chrome))
            .foregroundStyle(Color.brand(\.overlay0))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.brand(\.crust), in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text("Open a page by name (⌘P)"))
        .overlay(alignment: .trailing) {
            if IntelligenceService.shared.isAvailable(for: window.project) {
                Button {
                    window.showAsk()
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.brand(\.magic))
                        .accessibilityLabel(Text("Ask your project"))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 40)
                .help(Text("Ask your project (⇧⌘A)"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func emptyProject(of project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if project.kind == .unsorted {
                Text("Markdown files opened from Finder that belong to no project are kept here.")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.subtext))
            } else {
                Text("This grimoire is empty. Bind a folder to begin.")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.subtext))
            }
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
