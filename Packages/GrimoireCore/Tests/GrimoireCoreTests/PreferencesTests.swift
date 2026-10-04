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
        preferences.tabWidth = 2
        preferences.wordCount = .always
        let reopened = Preferences(defaults: defaults)
        #expect(reopened.opensInRaw)
        #expect(reopened.autosaveDelay == 10)
        #expect(reopened.fileExtensions == ["md", "markdown"])
        #expect(reopened.imageLocation == .projectFolder)
        #expect(reopened.proseFont == "New York")
        #expect(reopened.typewriterScrolling)
        #expect(reopened.tabWidth == 2)
        #expect(reopened.wordCount == .always)

        reopened.resetEditor()
        #expect(!reopened.typewriterScrolling)
        #expect(reopened.tabWidth == 4)
        // Fonts are reset on their own, from Appearance.
        #expect(reopened.proseFont == "New York")
        reopened.resetFonts()
        #expect(reopened.proseFont == "Geist")
        // Resetting the editor leaves General alone.
        #expect(reopened.opensInRaw)
    }

    @Test func shortcutsOverrideTheirDefaults() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.shortcut(for: .save) == KeyCombo("s"))
        let custom = KeyCombo("y", [.control, .command])
        preferences.setShortcut(custom, for: .save)
        preferences.setShortcut(nil, for: .print)

        let reopened = Preferences(defaults: defaults)
        #expect(reopened.shortcut(for: .save) == custom)
        #expect(reopened.shortcut(for: .print) == nil)
        #expect(reopened.action(using: custom) == .save)
        #expect(reopened.action(using: custom, except: .save) == nil)

        // Choosing the default again forgets the override.
        reopened.setShortcut(ShortcutAction.save.defaultCombo, for: .save)
        #expect(reopened.shortcutOverrides[.save] == nil)
        reopened.resetShortcuts()
        #expect(reopened.shortcut(for: .print) == ShortcutAction.print.defaultCombo)
    }

    @Test func defaultShortcutsDontCollide() {
        let combos = ShortcutAction.allCases.map(\.defaultCombo)
        #expect(Set(combos).count == combos.count)
    }

    @Test func writesShortcutsLikeMenus() {
        #expect(KeyCombo("c", [.option, .shift, .command]).display == "⌥⇧⌘C")
        #expect(KeyCombo(.return).display == "⌘↩")
        #expect(KeyCombo("n", [.control, .command]).display == "⌃⌘N")
        #expect(KeyCombo("N").key == "n")
        #expect(!KeyCombo("a", [.shift]).isMenuShortcut)
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

    @Test func spellingFollowsTheSystemUntilChanged() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.smartQuotes)
        #expect(preferences.checksSpelling)
        preferences.smartQuotes = true
        #expect(Preferences(defaults: defaults).smartQuotes)
    }
}
