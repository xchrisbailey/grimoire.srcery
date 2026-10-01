import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

/// Settings › Intelligence: whether the on-device AI features are on, whether long pages may
/// use Private Cloud Compute, and which projects keep them off.
struct IntelligenceSettings: View {
    @State private var preferences = Preferences.shared
    @State private var service = IntelligenceService.shared
    @Environment(ProjectLibrary.self) private var library
    @State private var project: Project.ID?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(service.status(for: nil) == .ready ? Color.brand(\.string) : Color.brand(\.overlay0))
                            .frame(width: 7, height: 7)
                        Text(service.status(for: nil).message ?? String(localized: "Ready, on this Mac"))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Use Apple Intelligence in Grimoire", isOn: $preferences.intelligenceEnabled)
                Toggle("Allow Private Cloud Compute for long pages", isOn: $preferences.allowsPrivateCloud)
                    .disabled(!preferences.intelligenceEnabled)
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "Everything runs on this Mac by default, and nothing leaves it. With Private Cloud Compute on, pages too long for the on-device model go to Apple's private servers, which keep nothing."
                )
                .foregroundStyle(.secondary)
            }
            if !library.projects.isEmpty {
                Section("Per project") {
                    Picker("Project", selection: $project) {
                        ForEach(library.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    if let id = project, let current = library.project(id) {
                        Toggle(
                            "Turn off intelligence for this project",
                            isOn: Binding(
                                get: { current.overrides.intelligenceOff == true },
                                set: { off in library.update(id) { $0.overrides.intelligenceOff = off ? true : nil } }))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.refresh()
            project = project ?? library.projects.first?.id
        }
    }
}
