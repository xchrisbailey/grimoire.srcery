import GrimoireCore
import GrimoireEditor
import SwiftUI

/// The card at the top of the sidebar: the current project, with a menu to switch,
/// create, rename or delete projects.
struct ProjectSwitcher: View {
    let window: WindowState

    @State private var name = ""
    @State private var confirmingDelete = false

    private var library: ProjectLibrary { window.library }
    private var current: Project? { window.project }

    var body: some View {
        Menu {
            ForEach(library.projects) { project in
                Toggle(
                    isOn: Binding(
                        get: { project.id == window.projectID },
                        set: { if $0 { window.selectProject(project.id) } })
                ) {
                    Label(project.name, systemImage: project.icon)
                }
            }
            if !library.projects.isEmpty { Divider() }
            Button("New Project…") { window.projectPrompt = .new }
            if let current {
                Button("Rename Project…") { window.projectPrompt = .rename(current.id) }
                Button("Delete Project…", role: .destructive) { confirmingDelete = true }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: current?.icon ?? "book.closed")
                    .foregroundStyle(Color.brand(\.magic))
                Text(current?.name ?? String(localized: "No Project"))
                    .brandFont(.chrome)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.brand(\.ink))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Color.brand(\.overlay1))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.brand(\.page), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.brand(\.surface0)))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onChange(of: window.projectPrompt, initial: true) {
            if case .rename(let id) = window.projectPrompt { name = library.project(id)?.name ?? "" } else { name = "" }
        }
        .alert(namingTitle, isPresented: isNaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button(namingConfirm) { finishNaming() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .confirmationDialog(
            String(localized: "Delete “\(current?.name ?? "")”?"), isPresented: $confirmingDelete
        ) {
            Button("Delete Project", role: .destructive) { deleteCurrent() }
        } message: {
            Text("The project is removed from Grimoire. Its folders and files stay on disk.")
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { window.projectPrompt != nil }, set: { if !$0 { window.projectPrompt = nil } })
    }

    private var namingTitle: String {
        if case .rename = window.projectPrompt {
            String(localized: "Rename Project")
        } else {
            String(localized: "New Project")
        }
    }

    private var namingConfirm: String {
        if case .rename = window.projectPrompt { String(localized: "Rename") } else { String(localized: "Create") }
    }

    private func finishNaming() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let prompt = window.projectPrompt else { return }
        switch prompt {
        case .new:
            window.selectProject(library.createProject(named: trimmed).id)
        case .rename(let id):
            library.update(id) { $0.name = trimmed }
        }
        window.projectPrompt = nil
    }

    private func deleteCurrent() {
        guard let current else { return }
        window.selectProject(nil)
        library.deleteProject(current.id)
        window.selectProject(library.projects.first?.id)
    }
}
