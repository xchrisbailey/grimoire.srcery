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
    @State private var localAssignment: Result<FolderTemplateAssignment?, Error> = .success(nil)
    @State private var effectiveAssignment: Result<FolderTemplateAssignment?, Error> = .success(nil)
    @State private var editableSource: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Content Template").font(.headline)
            LabeledContent("Folder") {
                Text(folder.path(percentEncoded: false)).textSelection(.enabled)
            }
            localChoice
            effectiveChoice
            Text("This choice applies to this folder and its descendants within this bound root in this project.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Inherit") { changeChoice { try workspace.inheritTemplate(in: folder) } }
                Menu("Use a template") {
                    Button("Choose Existing File…", action: chooseSource)
                    Button("Create Template…", action: createSource)
                }
                Button("No template") { changeChoice { try workspace.disableTemplate(in: folder) } }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear(perform: refreshChoices)
        .onChange(of: workspace.project) { refreshChoices() }
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
                    """
                    The empty source was created at \(source.url.path(percentEncoded: false)), but its assignment \
                    was not saved. The previous choice is unchanged. After fixing project settings, use \
                    Choose Existing File… to assign this source; do not create it again.
                    """
                )
            }
        }
    }

    @ViewBuilder private var localChoice: some View {
        switch localAssignment {
        case .failure(let failure):
            Text(failure.localizedDescription).foregroundStyle(.secondary)
        case .success(.some(let assignment)):
            if assignment.state == .unresolved {
                Text("Unresolved folder template assignment (inactive)")
            }
            switch assignment.choice {
            case .useSource:
                LabeledContent("Folder Choice", value: String(localized: "Use a template"))
            case .noTemplate:
                LabeledContent("Folder Choice", value: String(localized: "No template"))
            }
        case .success(.none):
            LabeledContent("Folder Choice", value: String(localized: "Inherit"))
        }
    }

    @ViewBuilder private var effectiveChoice: some View {
        switch effectiveAssignment {
        case .failure(let failure):
            Text(failure.localizedDescription).foregroundStyle(.secondary)
        case .success(.some(let assignment)):
            let local = try? localAssignment.get()
            if local?.owner == assignment.owner {
                LabeledContent("Owning Folder", value: displayPath(assignment.owner))
            } else {
                LabeledContent("Inherited From", value: displayPath(assignment.owner))
            }
            switch assignment.choice {
            case .useSource(let source):
                LabeledContent("Template Source", value: displayPath(source)).textSelection(.enabled)
                if let source = editableSource {
                    Button("Edit Template") {
                        actions.editTemplateAfterDismissal(source)
                        dismiss()
                    }
                }
            case .noTemplate:
                Text("No template (effective choice)")
            }
        case .success(.none):
            Text("No effective content template.")
        }
    }

    private func displayPath(_ reference: FileReference) -> String {
        if let url = workspace.url(for: reference) { return url.path(percentEncoded: false) }
        let root = workspace.project?.root(reference.rootID)?.displayName ?? reference.rootID.uuidString
        return root + " [" + reference.rootID.uuidString + "]/" + reference.relativePath
    }

    private func changeChoice(_ edit: () throws -> Void) {
        unassignedSource = nil
        do { try edit() } catch { self.error = error }
    }

    private func refreshChoices() {
        // Inspection refreshes bound-root access; do that on events, not during view evaluation.
        localAssignment = Result(catching: { try workspace.templateAssignment(for: folder) })
        effectiveAssignment = Result(catching: { try workspace.effectiveTemplateAssignment(for: folder) })
        editableSource = (try? effectiveAssignment.get()).flatMap { try? workspace.templateSourceURL(for: $0) }
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
                """
                Create an empty Markdown template source inside a folder bound to this project. \
                Existing files are never replaced; a numbered name is used instead.
                """
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
