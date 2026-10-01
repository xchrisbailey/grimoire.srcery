import GrimoireCore
import GrimoireEditor
import SwiftUI

struct ContentView: View {
    @Environment(ProjectLibrary.self) private var library
    @State private var selectedProjectID: Project.ID?
    @State private var workspace: Workspace?
    @State private var selectedFile: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView(workspace: workspace, selectedProjectID: $selectedProjectID, selectedFile: $selectedFile)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            Group {
                if let selectedFile {
                    Text(selectedFile.lastPathComponent)
                        .brandFont(.heading)
                        .foregroundStyle(Color.brand(\.ink))
                } else {
                    Text("A blank page. Type / to cast a block.")
                        .brandFont(.body)
                        .foregroundStyle(Color.brand(\.overlay1))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brand(\.page))
        }
        .tint(Color.brand(\.magic))
        .frame(minWidth: 640, minHeight: 400)
        .onAppear {
            if library.projects.isEmpty { library.createProject(named: String(localized: "Grimoire")) }
            if selectedProjectID == nil { selectedProjectID = library.projects.first?.id }
            openWorkspace()
        }
        .onChange(of: selectedProjectID) { openWorkspace() }
        .onChange(of: selectedProjectID.flatMap(library.project)?.roots) { workspace?.sync() }
        .onDisappear { workspace?.deactivate() }
    }

    private func openWorkspace() {
        guard workspace?.projectID != selectedProjectID else { return }
        workspace?.deactivate()
        selectedFile = nil
        guard let selectedProjectID else {
            workspace = nil
            return
        }
        let workspace = Workspace(projectID: selectedProjectID, library: library)
        workspace.activate()
        self.workspace = workspace
    }
}
