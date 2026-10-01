import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Every command in the app as a palette row: the menu bar's commands, spells, themes and
/// appearance. Titles match the menu bar, which stays plain.
@MainActor
enum Incantations {
    static func items(
        for window: WindowState, openWindow: @escaping () -> Void, openSettings: @escaping () -> Void
    ) -> [PaletteItem] {
        file(window, openWindow: openWindow) + edit(window) + view(window) + spells(window) + themes()
            + app(openSettings: openSettings)
    }

    // MARK: - File

    private static func file(_ window: WindowState, openWindow: @escaping () -> Void) -> [PaletteItem] {
        var items: [PaletteItem] = []
        if window.folderForNewFiles != nil {
            items.append(
                item("file.new", String(localized: "New File"), "⌘N", icon: "doc.badge.plus", keywords: "conjure page")
                {
                    window.newFile()
                })
        }
        items.append(item("file.window", String(localized: "New Window"), "⌥⌘N", icon: "macwindow") { openWindow() })
        items.append(
            item("file.project", String(localized: "New Project…"), "⌃⌘N", icon: "book.closed") {
                window.projectPrompt = .new
            })
        if window.project != nil {
            items.append(
                item("file.bind", String(localized: "Add Folder…"), "⇧⌘O", icon: "folder.badge.plus", keywords: "bind")
                {
                    window.bindFolders()
                })
            items.append(
                item(
                    "file.summon", String(localized: "Open Quickly…"), "⌘P", icon: "magnifyingglass", keywords: "summon"
                ) {
                    window.showPalette(.summon)
                })
        }
        if window.document != nil {
            items.append(
                item("file.save", String(localized: "Save"), "⌘S", icon: "square.and.arrow.down") { window.save() })
        }
        items.append(
            item("file.close", String(localized: "Close"), "⌘W", icon: "xmark") {
                NSApp.keyWindow?.performClose(nil)
            })
        return items
    }

    // MARK: - Edit

    private static func edit(_ window: WindowState) -> [PaletteItem] {
        guard window.document != nil else { return [] }
        return editCommands.map { command in
            item(command.id, command.title, command.shortcut, icon: nil) { window.sendToEditor(command.action) }
        } + find(window)
    }

    /// The Edit menu's commands that go to the text view.
    private static let editCommands: [Command<Selector>] = [
        Command("edit.undo", String(localized: "Undo"), "⌘Z", Selector(("undo:"))),
        Command("edit.redo", String(localized: "Redo"), "⇧⌘Z", Selector(("redo:"))),
        Command("edit.cut", String(localized: "Cut"), "⌘X", #selector(NSText.cut(_:))),
        Command("edit.copy", String(localized: "Copy"), "⌘C", #selector(NSText.copy(_:))),
        Command("edit.paste", String(localized: "Paste"), "⌘V", #selector(NSText.paste(_:))),
        Command("edit.delete", String(localized: "Delete"), "", #selector(NSText.delete(_:))),
        Command("edit.selectAll", String(localized: "Select All"), "⌘A", #selector(NSText.selectAll(_:))),
        Command(
            "edit.spelling", String(localized: "Check Spelling While Typing"), "",
            #selector(NSTextView.toggleContinuousSpellChecking(_:))
        ),
        Command(
            "edit.grammar", String(localized: "Check Grammar With Spelling"), "",
            #selector(NSTextView.toggleGrammarChecking(_:))
        ),
        Command(
            "edit.correct", String(localized: "Correct Spelling Automatically"), "",
            #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
        ),
        Command(
            "edit.spellingPanel", String(localized: "Show Spelling and Grammar"), "⌘:",
            #selector(NSText.showGuessPanel(_:))
        ),
        Command("edit.checkNow", String(localized: "Check Document Now"), "⌘;", #selector(NSText.checkSpelling(_:))),
        Command(
            "edit.quotes", String(localized: "Smart Quotes"), "",
            #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))
        ),
        Command(
            "edit.dashes", String(localized: "Smart Dashes"), "",
            #selector(NSTextView.toggleAutomaticDashSubstitution(_:))
        ),
        Command(
            "edit.replacement", String(localized: "Text Replacement"), "",
            #selector(NSTextView.toggleAutomaticTextReplacement(_:))
        ),
        Command(
            "edit.substitutions", String(localized: "Show Substitutions"), "",
            #selector(NSTextView.orderFrontSubstitutionsPanel(_:))
        ),
        Command(
            "edit.smartPaste", String(localized: "Smart Copy/Paste"), "",
            #selector(NSTextView.toggleSmartInsertDelete(_:))
        ),
        Command(
            "edit.links", String(localized: "Smart Links"), "",
            #selector(NSTextView.toggleAutomaticLinkDetection(_:))
        ),
        Command(
            "edit.detectors", String(localized: "Data Detectors"), "",
            #selector(NSTextView.toggleAutomaticDataDetection(_:))
        ),
        Command("edit.upper", String(localized: "Make Upper Case"), "", #selector(NSResponder.uppercaseWord(_:))),
        Command("edit.lower", String(localized: "Make Lower Case"), "", #selector(NSResponder.lowercaseWord(_:))),
        Command("edit.capitalize", String(localized: "Capitalize"), "", #selector(NSResponder.capitalizeWord(_:))),
        Command("edit.speak", String(localized: "Start Speaking"), "", #selector(NSTextView.startSpeaking(_:))),
        Command("edit.stopSpeaking", String(localized: "Stop Speaking"), "", #selector(NSTextView.stopSpeaking(_:))),
        Command("edit.dictation", String(localized: "Start Dictation…"), "", Selector(("startDictation:"))),
        Command(
            "edit.emoji", String(localized: "Emoji & Symbols"), "⌃⌘Space",
            #selector(NSApplication.orderFrontCharacterPalette(_:))
        ),
    ]

    private static func find(_ window: WindowState) -> [PaletteItem] {
        let finds: [Command<NSTextFinder.Action>] = [
            Command("find.show", String(localized: "Find…"), "⌘F", .showFindInterface),
            Command("find.replace", String(localized: "Find and Replace…"), "⌥⌘F", .showReplaceInterface),
            Command("find.next", String(localized: "Find Next"), "⌘G", .nextMatch),
            Command("find.previous", String(localized: "Find Previous"), "⇧⌘G", .previousMatch),
            Command("find.selection", String(localized: "Use Selection for Find"), "⌘E", .setSearchString),
        ]
        var items = finds.map { command in
            item(command.id, command.title, command.shortcut, icon: "magnifyingglass") {
                window.sendFindAction(command.action)
            }
        }
        items.append(
            item("find.jump", String(localized: "Jump to Selection"), "⌘J", icon: nil) {
                window.sendToEditor(#selector(NSTextView.centerSelectionInVisibleArea(_:)))
            })
        return items
    }

    // MARK: - View

    private static func view(_ window: WindowState) -> [PaletteItem] {
        var items: [PaletteItem] = [
            item(
                "view.sidebar", String(localized: "Toggle Sidebar"), "⌃⌘S", icon: "sidebar.left", keywords: "show hide"
            ) {
                window.columnVisibility = window.columnVisibility == .detailOnly ? .all : .detailOnly
            },
            item("view.focus", String(localized: "Focus Mode"), "⇧⌘F", icon: "eye") {
                window.setFocusMode(!window.focusMode)
            },
        ]
        if window.project != nil {
            items.append(
                item("view.search", String(localized: "Find in Project…"), "⇧⌘E", icon: "doc.text.magnifyingglass") {
                    window.search.begin()
                })
        }
        if window.document != nil {
            let toRaw = window.editorMode == .preview
            items.append(
                item(
                    "view.raw", toRaw ? String(localized: "Show Raw Source") : String(localized: "Show Preview"), "⇧⌘R",
                    icon: "chevron.left.forwardslash.chevron.right", keywords: "raw preview mode"
                ) { window.editorMode = toRaw ? .raw : .preview })
            items.append(
                item("view.headings", String(localized: "Jump to Heading…"), "⇧⌘J", icon: "list.bullet.indent") {
                    window.showPalette(.headings)
                })
        }
        return items
    }

    // MARK: - Spells, themes, app

    /// Every spell, cast at the caret.
    private static func spells(_ window: WindowState) -> [PaletteItem] {
        guard window.document != nil else { return [] }
        return Spellbook.standard.map { spell in
            PaletteItem(
                id: "spell." + spell.id, title: String(localized: "Cast \(spell.title)"), subtitle: spell.subtitle,
                shortcut: spell.hint, icon: spell.icon, keywords: spell.aliases.joined(separator: " ")
            ) { window.editor.cast(spell) }
        }
    }

    private static func themes() -> [PaletteItem] {
        let library = ThemeLibrary.shared
        var items = library.themes.map { theme in
            PaletteItem(
                id: "theme." + theme.id,
                title: theme.isDark
                    ? String(localized: "Use \(theme.name) in Dark Mode")
                    : String(localized: "Use \(theme.name) in Light Mode"),
                icon: "paintpalette", keywords: "theme"
            ) {
                if theme.isDark { library.setDarkTheme(theme.id) } else { library.setLightTheme(theme.id) }
            }
        }
        let modes: [(AppearanceMode, String)] = [
            (.system, String(localized: "Appearance: Match System")), (.light, String(localized: "Appearance: Light")),
            (.dark, String(localized: "Appearance: Dark")),
        ]
        items += modes.map { mode, title in
            PaletteItem(
                id: "appearance." + mode.rawValue, title: title, icon: "circle.lefthalf.filled", keywords: "theme"
            ) {
                library.setAppearance(mode)
                library.applyAppearance()
            }
        }
        return items
    }

    private static func app(openSettings: @escaping () -> Void) -> [PaletteItem] {
        [
            item("app.settings", String(localized: "Settings…"), "⌘,", icon: "gearshape") { openSettings() },
            item("app.about", String(localized: "About Grimoire"), "", icon: "info.circle") { AboutPanel.show() },
            item("window.minimize", String(localized: "Minimize"), "⌘M", icon: nil) {
                NSApp.keyWindow?.performMiniaturize(nil)
            },
            item("window.zoom", String(localized: "Zoom"), "", icon: nil) { NSApp.keyWindow?.performZoom(nil) },
            item("window.front", String(localized: "Bring All to Front"), "", icon: nil) { NSApp.arrangeInFront(nil) },
            item("app.hide", String(localized: "Hide Grimoire"), "⌘H", icon: nil) { NSApp.hide(nil) },
            item("app.hideOthers", String(localized: "Hide Others"), "⌥⌘H", icon: nil) {
                NSApp.hideOtherApplications(nil)
            },
            item("app.showAll", String(localized: "Show All"), "", icon: nil) { NSApp.unhideAllApplications(nil) },
            item("app.help", String(localized: "Grimoire Help"), "⌘?", icon: "questionmark.circle") {
                NSApp.showHelp(nil)
            },
            item("app.quit", String(localized: "Quit Grimoire"), "⌘Q", icon: "power") { NSApp.terminate(nil) },
        ]
    }

    /// A menu command: its id, menu title, shortcut, and what it sends.
    private struct Command<Action> {
        var id: String
        var title: String
        var shortcut: String
        var action: Action

        init(_ id: String, _ title: String, _ shortcut: String, _ action: Action) {
            (self.id, self.title, self.shortcut, self.action) = (id, title, shortcut, action)
        }
    }

    private static func item(
        _ id: String, _ title: String, _ shortcut: String, icon: String?, keywords: String = "",
        perform: @escaping () -> Void
    ) -> PaletteItem {
        PaletteItem(id: id, title: title, shortcut: shortcut, icon: icon, keywords: keywords, perform: perform)
    }
}
