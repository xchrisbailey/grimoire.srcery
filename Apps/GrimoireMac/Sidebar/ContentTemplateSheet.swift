import AppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

/// Configuration only: document creation does not consume these choices yet.
struct ContentTemplateSheet: View {
    let folder: URL
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?

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
                Button("Choose Existing File…", action: chooseSource)
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
