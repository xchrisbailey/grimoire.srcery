import GrimoireCore
import SwiftUI

struct DestructiveLifecyclePrompt: ViewModifier {
    @Bindable var actions: FileActions
    let workspace: Workspace?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { actions.destructivePlan != nil },
                set: { if !$0 { actions.destructivePlan = nil } })
        ) {
            if let plan = actions.destructivePlan {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title(plan)).font(.headline)
                    Text(plan.item.path).textSelection(.enabled)
                    Text(explanation(plan))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choices to remove").font(.headline)
                            ForEach(plan.removedChoices, id: \.owner) { assignment in
                                Text(referencePath(assignment.owner))
                                switch assignment.choice {
                                case .noTemplate: Text("No template")
                                case .useSource(let source): Text(referencePath(source))
                                }
                            }
                            Text("Remaining assignments with broken sources").font(.headline)
                            ForEach(plan.brokenDependencies, id: \.owner) { assignment in
                                Text(referencePath(assignment.owner))
                                if case .useSource(let source) = assignment.choice { Text(referencePath(source)) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let notice = actions.destructiveNotice { Text(notice).foregroundStyle(.secondary) }
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { actions.destructivePlan = nil }
                        Button(title(plan), role: .destructive) {
                            if let workspace { actions.confirmDestructiveOperation(workspace: workspace) }
                        }
                    }
                }.padding(24).frame(width: 560, height: 440)
            }
        }
    }

    private func referencePath(_ reference: FileReference) -> String {
        workspace?.url(for: reference)?.path ?? "[" + reference.rootID.uuidString + "]/" + reference.relativePath
    }

    private func title(_ plan: DestructiveLifecyclePlan) -> String {
        switch plan.action {
        case .unbind: String(localized: "Unbind Folder")
        case .trash: String(localized: "Banish")
        case .finishTrash: String(localized: "Finish configuration removal…")
        }
    }

    private func explanation(_ plan: DestructiveLifecyclePlan) -> String {
        switch plan.action {
        case .unbind:
            String(localized: "This removes the binding and its owned template assignments and opt-outs.")
                + "\n" + String(localized: "Files on disk stay unchanged. Rebinding starts unconfigured.")
        case .trash:
            String(localized: "This item goes to the Trash.")
                + "\n"
                + String(localized: "Its explicit and descendant choices are removed only after successful trash.")
                + "\n" + String(localized: "Restoring it requires reassignment.")
                + "\n" + String(localized: "Remaining assignments keep broken source references without a fallback.")
        case .finishTrash:
            String(
                localized:
                    "This applies only the recorded configuration removals and clears this trash recovery record.")
                + "\n" + String(localized: "It does not move, delete, or restore any file.")
                + "\n" + String(localized: "The item's trash outcome is unknown, even if it has reappeared.")
                + "\n" + String(localized: "Removed choices require reassignment.")
                + "\n" + String(localized: "Remaining assignments retain their source references, which may be broken.")
        }
    }
}
