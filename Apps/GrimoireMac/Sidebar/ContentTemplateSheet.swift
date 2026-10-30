import AppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentTemplateSheet: View {
    let folder: URL
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?

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
                }
                Button("No template") { changeChoice { try workspace.disableTemplate(in: folder) } }
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
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder private var localChoice: some View {
        switch Result(catching: { try workspace.templateAssignment(for: folder) }) {
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
        switch Result(catching: { try workspace.effectiveTemplateAssignment(for: folder) }) {
        case .failure(let failure):
            Text(failure.localizedDescription).foregroundStyle(.secondary)
        case .success(.some(let assignment)):
            let local = try? workspace.templateAssignment(for: folder)
            if local?.owner == assignment.owner {
                LabeledContent("Owning Folder", value: displayPath(assignment.owner))
            } else {
                LabeledContent("Inherited From", value: displayPath(assignment.owner))
            }
            switch assignment.choice {
            case .useSource(let source):
                LabeledContent("Template Source", value: displayPath(source)).textSelection(.enabled)
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
        do { try edit() } catch { self.error = error }
    }

    private func chooseSource() {
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
}
