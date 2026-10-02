import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Settings › General: how files open and save, where new files go, how the sidebar lists
/// them, where images go, and how exports treat line breaks.
struct GeneralSettings: View {
    @State private var preferences = Preferences.shared
    @Environment(ProjectLibrary.self) private var library
    @State private var extensionsText = ""
    @State private var overrideProject: Project.ID?
    @State private var projectExtensionsText = ""

    var body: some View {
        Form {
            Section {
                Picker("Open files in", selection: $preferences.opensInRaw) {
                    Text("Preview").tag(false)
                    Text("Raw").tag(true)
                }
                Toggle("Reopen the last page when Grimoire starts", isOn: $preferences.restoresLastSession)
                Picker("Save edits after", selection: $preferences.autosaveDelay) {
                    Text("1 second").tag(1.0)
                    Text("3 seconds").tag(3.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
            }
            Section {
                TextField("List files ending in", text: $extensionsText, prompt: Text("md, mdx"))
                    .onSubmit { preferences.fileExtensions = Preferences.parseExtensions(extensionsText) }
                Picker("Save pasted images in", selection: $preferences.imageLocation) {
                    imageLocationOptions
                }
            } footer: {
                Text("Separate extensions with commas. Pasted images go in an assets folder.")
                    .foregroundStyle(.secondary)
            }
            NewFileSettings(preferences: preferences)
            SidebarListingSettings(preferences: preferences)
            Section {
                Toggle("Strict line breaks", isOn: $preferences.strictLineBreaks)
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "On, a single line break joins the lines in exports, printing and rich text, as markdown does. Off, it stays a line break. Leave an empty line to start a new paragraph either way."
                )
                .foregroundStyle(.secondary)
            }
            projectSection
        }
        .formStyle(.grouped)
        .onAppear {
            extensionsText = preferences.fileExtensions.joined(separator: ", ")
            overrideProject = overrideProject ?? library.projects.first?.id
            loadProjectExtensions()
        }
        .onChange(of: overrideProject) { loadProjectExtensions() }
        .onDisappear { preferences.fileExtensions = Preferences.parseExtensions(extensionsText) }
    }

    @ViewBuilder private var imageLocationOptions: some View {
        Text("Next to the page").tag(ImageLocation.besideFile)
        Text("At the top of its folder").tag(ImageLocation.projectFolder)
    }

    /// One project's own list of extensions and image folder, overriding the defaults.
    @ViewBuilder private var projectSection: some View {
        if !library.projects.isEmpty {
            Section {
                Picker("Project", selection: $overrideProject) {
                    ForEach(library.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                if let id = overrideProject, let project = library.project(id) {
                    Toggle(
                        "Use its own file extensions",
                        isOn: Binding(
                            get: { project.overrides.fileExtensions != nil },
                            set: { useOwn in
                                library.update(id) {
                                    $0.overrides.fileExtensions = useOwn ? preferences.fileExtensions : nil
                                }
                                loadProjectExtensions()
                            }))
                    if project.overrides.fileExtensions != nil {
                        TextField("List files ending in", text: $projectExtensionsText, prompt: Text("md, mdx"))
                            .onSubmit { saveProjectExtensions() }
                    }
                    Picker(
                        "Save pasted images in",
                        selection: Binding(
                            get: { project.overrides.imageLocation },
                            set: { location in library.update(id) { $0.overrides.imageLocation = location } })
                    ) {
                        Text("Same as above").tag(ImageLocation?.none)
                        Text("Next to the page").tag(Optional(ImageLocation.besideFile))
                        Text("At the top of its folder").tag(Optional(ImageLocation.projectFolder))
                    }
                }
            } header: {
                Text("Per project")
            } footer: {
                Text("A project's own settings are saved with the project.")
                    .foregroundStyle(.secondary)
            }
            .onDisappear { saveProjectExtensions() }
        }
    }

    private func loadProjectExtensions() {
        let project = overrideProject.flatMap(library.project)
        projectExtensionsText = preferences.fileExtensions(for: project).joined(separator: ", ")
    }

    private func saveProjectExtensions() {
        guard let id = overrideProject, library.project(id)?.overrides.fileExtensions != nil else { return }
        let parsed = Preferences.parseExtensions(projectExtensionsText)
        library.update(id) { $0.overrides.fileExtensions = parsed }
    }
}
