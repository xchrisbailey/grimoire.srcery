import AppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentTemplateSheet: View {
    let folder: URL
    let workspace: Workspace
    let actions: FileActions
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var unassignedSource: PublishedDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Template").font(.headline)
            LabeledContent("Owning Folder") {
                Text(folder.path(percentEncoded: false)).textSelection(.enabled)
            }
            choice
            Text("This choice applies to new documents in this exact folder in this project.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Menu("Use a template") {
                    Button("Choose Existing File…", action: chooseSource)
                    Button("Create Template…", action: createSource)
                }
                if let source = editableSource {
                    Button("Edit Template") {
                        actions.editTemplateAfterDismissal(source)
                        dismiss()
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .alert(
            error?.localizedDescription ?? "",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            if let source = unassignedSource {
                Button("Open Created Source") {
                    actions.openTemplateAfterDismissal(source, workspace: workspace)
                    dismiss()
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let source = unassignedSource {
                Text(
                    "The empty source was created at \(source.url.path(percentEncoded: false)), but its assignment was not saved. The previous choice is unchanged. After fixing project settings, use Choose Existing File… to assign this source; do not create it again."
                )
            }
        }
    }

    // Exact-folder adapter until #87 supplies Workspace.effectiveTemplateAssignment(for:).
    private var editableSource: URL? {
        guard let assignment = try? workspace.templateAssignment(for: folder), assignment.state == .active else {
            return nil
        }
        return try? workspace.templateSourceURL(for: assignment)
    }

    @ViewBuilder private var choice: some View {
        switch Result(catching: { try workspace.templateAssignment(for: folder) }) {
        case .failure(let failure):
            Text(failure.localizedDescription).foregroundStyle(.secondary)
        case .success(.some(let assignment)):
            if assignment.state == .unresolved {
                Text("Unresolved folder template assignment (inactive)")
            }
            switch assignment.choice {
            case .useSource(let source):
                LabeledContent("Template Source") {
                    let root = workspace.project?.root(source.rootID)?.displayName ?? source.rootID.uuidString
                    let path = workspace.url(for: source)?.path(percentEncoded: false)
                    Text(path ?? root + " [" + source.rootID.uuidString + "]/" + source.relativePath)
                        .textSelection(.enabled)
                }
            case .noTemplate:
                Text("No template (explicit choice)")
            }
        case .success(.none):
            Text("No explicit content template choice for this folder.")
        }
    }

    private func chooseSource() {
        unassignedSource = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "mdx") ?? .text,
        ]
        panel.directoryURL = folder
        panel.message = String(localized: "Choose a Markdown template source inside a folder bound to this project.")
        panel.prompt = String(localized: "Use Template")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            try workspace.assignTemplate(source, to: folder)
        } catch {
            self.error = error
        }
    }

    private func createSource() {
        unassignedSource = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = false
        panel.directoryURL = folder
        panel.nameFieldStringValue = "Template.md"
        panel.prompt = String(localized: "Create Template")
        panel.message = String(
            localized:
                "Create an empty Markdown template source inside a folder bound to this project. Existing files are never replaced; a numbered name is used instead."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard url.pathExtension.lowercased() == "md" else { throw TemplateAssignmentError.ineligibleSource }
            let plan = try workspace.prepareTemplateSource(in: url.deletingLastPathComponent(), assigningTo: folder)
            switch workspace.createTemplateSource(plan, named: url.deletingPathExtension().lastPathComponent) {
            case .assigned(let source):
                actions.openTemplateAfterDismissal(source, workspace: workspace)
                dismiss()
            case .unassigned(let source, let failure):
                workspace.refresh(of: source.url)
                unassignedSource = source
                error = failure
            case .failed(let failure):
                error = failure
            case .cancelled:
                break
            }
        } catch {
            self.error = error
        }
    }
}
