import AppKit
import GrimoireCore
import SwiftUI

struct TemplateRecoverySection: View {
    let workspace: Workspace
    let actions: FileActions

    var body: some View {
        Section("Content Templates") {
            ForEach(workspace.unresolvedTemplateAssignments, id: \.owner) { assignment in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unresolved folder template assignment (inactive)")
                    Text(path(assignment.owner)).textSelection(.enabled)
                    switch assignment.choice {
                    case .useSource(let source):
                        Text("Template Source: \(path(source))").textSelection(.enabled)
                    case .noTemplate:
                        Text("No template")
                    }
                    HStack {
                        Button("Locate Folder…") { locate(assignment) }
                        Button("Remove Assignment") { recover(assignment, locating: nil) }
                    }
                }
                .brandFont(.chrome)
                .controlSize(.small)
            }
            Button("Check Folder Template Assignments") {
                workspace.refreshTemplateAssignments()
                if let error = workspace.lastError { actions.error = error }
            }
            .controlSize(.small)
        }
    }

    private func path(_ reference: FileReference) -> String {
        templateRecoveryPath(reference, workspace: workspace)
    }

    private func locate(_ assignment: FolderTemplateAssignment) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose the owning folder inside an accessible binding in this project.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recover(assignment, locating: url)
    }

    private func recover(_ assignment: FolderTemplateAssignment, locating destination: URL?) {
        do {
            let plan = try workspace.prepareTemplateRecovery(assignment, locating: destination)
            let alert = NSAlert()
            alert.messageText =
                destination == nil ? String(localized: "Remove Assignment") : String(localized: "Locate Folder…")
            let newOwner = destination?.path(percentEncoded: false) ?? String(localized: "Inherit")
            alert.informativeText = String(
                localized:
                    """
                    Owning folder: \(path(assignment.owner))
                    New choice location: \(newOwner)
                    This changes only this explicit choice and its inherited scope in this project. \
                    Nearer choices and separate bindings are unchanged. Template source references and files \
                    are unchanged; a broken source still needs separate repair.
                    """)
            alert.addButton(withTitle: String(localized: "Confirm"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try workspace.confirmTemplateRecovery(plan)
        } catch { actions.error = error }
    }
}

func templateRecoveryPath(_ reference: FileReference, workspace: Workspace) -> String {
    if let url = workspace.url(for: reference) { return url.path(percentEncoded: false) }
    let root = workspace.project?.root(reference.rootID)?.displayName ?? reference.rootID.uuidString
    return root + " [" + reference.rootID.uuidString + "]/" + reference.relativePath
}
