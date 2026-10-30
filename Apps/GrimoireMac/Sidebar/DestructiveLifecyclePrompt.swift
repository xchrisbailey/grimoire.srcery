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
                    Text("Unbind Folder").font(.headline)
                    Text(plan.item.path).textSelection(.enabled)
                    Text(
                        "This removes the binding and its owned template assignments and opt-outs. Files on disk stay unchanged. Rebinding starts unconfigured."
                    )
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choices to remove").font(.headline)
                            ForEach(plan.removedChoices, id: \.owner) { assignment in
                                Text(referencePath(assignment.owner))
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
                        Button("Unbind Folder", role: .destructive) {
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
}
