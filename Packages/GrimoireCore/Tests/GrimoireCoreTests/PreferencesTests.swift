import Foundation
import Testing

@testable import GrimoireCore

@MainActor @Suite struct PreferencesTests {
    func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "grimoire-tests-\(UUID().uuidString)")!
    }

    @Test func startsWithTheBrandDefaults() {
        let preferences = Preferences(defaults: makeDefaults())
        #expect(!preferences.opensInRaw)
        #expect(preferences.restoresLastSession)
        #expect(preferences.autosaveDelay == 1)
        #expect(preferences.fileExtensions == ["md", "mdx"])
        #expect(preferences.imageLocation == .besideFile)
        #expect(preferences.proseFont == "Geist")
        #expect(preferences.proseSize == 15.5)
        #expect(preferences.codeFont == "Geist Mono")
        #expect(preferences.codeSize == 14)
        #expect(preferences.lineHeight == 1.7)
        #expect(preferences.maxLineWidth == 680)
        #expect(!preferences.showsMarkers)
        #expect(!preferences.typewriterScrolling)
        #expect(preferences.focusDimming)
    }

    @Test func savesEveryChange() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.opensInRaw = true
        preferences.autosaveDelay = 10
        preferences.fileExtensions = ["md", "markdown"]
        preferences.imageLocation = .projectFolder
        preferences.proseFont = "New York"
        preferences.typewriterScrolling = true
        let reopened = Preferences(defaults: defaults)
        #expect(reopened.opensInRaw)
        #expect(reopened.autosaveDelay == 10)
        #expect(reopened.fileExtensions == ["md", "markdown"])
        #expect(reopened.imageLocation == .projectFolder)
        #expect(reopened.proseFont == "New York")
        #expect(reopened.typewriterScrolling)

        reopened.resetEditor()
        #expect(!reopened.typewriterScrolling)
        // Fonts are reset on their own, from Appearance.
        #expect(reopened.proseFont == "New York")
        reopened.resetFonts()
        #expect(reopened.proseFont == "Geist")
        // Resetting the editor leaves General alone.
        #expect(reopened.opensInRaw)
    }

    @Test func readsExtensionLists() {
        #expect(Preferences.parseExtensions("md, .MDX markdown;md") == ["md", "mdx", "markdown"])
        #expect(Preferences.parseExtensions("  ") == ["md", "mdx"])
        #expect(Preferences.parseExtensions("txt, a/b") == ["txt"])
    }

    @Test func projectsOverrideTheDefaults() {
        let preferences = Preferences(defaults: makeDefaults())
        var project = Project(name: "Blog")
        #expect(preferences.fileExtensions(for: project) == ["md", "mdx"])
        #expect(preferences.imageLocation(for: nil) == .besideFile)
        project.overrides = ProjectOverrides(fileExtensions: ["mdx"], imageLocation: .projectFolder)
        #expect(preferences.fileExtensions(for: project) == ["mdx"])
        #expect(preferences.imageLocation(for: project) == .projectFolder)
    }

    @Test func projectsSavedBeforeOverridesStillLoad() throws {
        let json = """
            {"version": 1, "projects": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Old",
            "icon": "book.closed", "color": "magic", "roots": [], "expandedFolders": []}]}
            """
        let scratch = try Scratch()
        let file = try scratch.file("projects.json", json)
        let projects = try ProjectStore(fileURL: file).load()
        #expect(projects.first?.name == "Old")
        #expect(projects.first?.overrides == ProjectOverrides())
        #expect(projects.first?.dictionary == [])
    }

    @Test func spellingFollowsTheSystemUntilChanged() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.smartQuotes)
        #expect(preferences.checksSpelling)
        preferences.smartQuotes = true
        #expect(Preferences(defaults: defaults).smartQuotes)
    }

    @Test func readsSimpleFrontmatterValues() {
        let document = Document(parsing: "---\ntitle: \"Potions\"\nlang: de-DE\nnested:\n  lang: fr\n---\n\nText\n")
        #expect(document.frontmatter?.value(forKey: "lang") == "de-DE")
        #expect(document.frontmatter?.value(forKey: "title") == "Potions")
        #expect(document.frontmatter?.value(forKey: "missing") == nil)
    }

    @Test func changingExtensionsRescansTheTree() async throws {
        let scratch = try Scratch()
        let notes = try scratch.folder("notes")
        try scratch.file("notes/spells.md")
        try scratch.file("notes/runes.txt")
        let library = ProjectLibrary(store: ProjectStore(fileURL: scratch.url.appending(path: "projects.json")))
        let project = library.createProject(named: "Notes")
        try library.bindFolder(notes, to: project.id)
        let workspace = Workspace(projectID: project.id, library: library)
        workspace.activate()
        defer { workspace.deactivate() }
        try await until { workspace.folders.first?.status == .available }
        #expect(workspace.folders.first?.tree?.documents.map(\.name) == ["spells.md"])

        workspace.setExtensions(["md", "txt"])
        try await until { workspace.folders.first?.tree?.documents.count == 2 }
        #expect(workspace.folders.first?.tree?.documents.map(\.name) == ["runes.txt", "spells.md"])
    }
}
