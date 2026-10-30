import GrimoireCore
import SwiftUI

struct DocumentCreationSheet: View {
    @Bindable var actions: FileActions
    let workspace: Workspace
    @FocusState private var nameFocused: Bool

    private var validation: String? {
        guard actions.creationNameEdited else { return nil }
        do {
            try DocumentNameError.validate(actions.creationStem)
            return nil
        } catch { return error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Conjure a page").font(.headline)
            if let plan = actions.creationPlan {
                LabeledContent("Destination", value: plan.destination.path)
                LabeledContent("Template source", value: sourcePath(plan))
                if let assignment = plan.assignment {
                    LabeledContent("Owning Folder", value: ownerPath(assignment.owner))
                }
            }
            HStack {
                TextField(
                    "Name",
                    text: Binding(
                        get: { actions.creationStem },
                        set: {
                            actions.creationStem = $0
                            actions.creationNameEdited = true
                        })
                )
                .focused($nameFocused)
                .onSubmit { confirm() }
                Text(verbatim: ".md").foregroundStyle(.secondary)
            }
            if let message = validation ?? actions.creationNotice {
                Text(message).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { actions.cancelCreation(workspace: workspace) }
                    .keyboardShortcut(.cancelAction)
                if actions.creationSourceFailed {
                    Button("Create Empty Once") {
                        actions.confirmCreation(workspace: workspace, recovery: .createEmptyOnce)
                    }
                    .disabled(validation != nil)
                }
                Button(actions.creationSourceFailed || actions.creationAttemptFailed ? "Retry" : "Create") { confirm() }
                    .keyboardShortcut(.defaultAction).disabled(validation != nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { nameFocused = true }
    }

    private func confirm() {
        guard validation == nil else { return }
        actions.confirmCreation(workspace: workspace)
    }

    private func ownerPath(_ owner: FileReference) -> String {
        workspace.url(for: owner)?.path ?? "[" + owner.rootID.uuidString + "]/" + owner.relativePath
    }

    private func sourcePath(_ plan: DocumentCreationPlan) -> String {
        if let source = plan.source { return source.path }
        if case .useSource(let reference) = plan.assignment?.choice { return ownerPath(reference) }
        return String(localized: "No template")
    }
}

struct CreatedDocumentOpenError: LocalizedError {
    let url: URL
    var errorDescription: String? {
        String(localized: "The document was created at \(url.path), but couldn’t be opened.")
            + "\n" + String(localized: "Open that file; don’t create another copy.")
    }
}

struct DocumentCreationPrompt: ViewModifier {
    @Bindable var actions: FileActions
    let workspace: Workspace?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { actions.creationPlan != nil },
                set: {
                    if !$0, let workspace { actions.cancelCreation(workspace: workspace) }
                }),
            onDismiss: { actions.creationDismissed() },
            content: {
                if let workspace { DocumentCreationSheet(actions: actions, workspace: workspace) }
            })
    }
}
