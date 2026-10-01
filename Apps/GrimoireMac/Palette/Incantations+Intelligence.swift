import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

extension Incantations {
    /// AI commands, offered only when the model can run for this project.
    static func intelligence(_ window: WindowState) -> [PaletteItem] {
        guard window.intelligenceReady else { return [] }
        var items = Spellbook.intelligence.map { spell in
            PaletteItem(
                id: "spell." + spell.id, title: String(localized: "Cast \(spell.title)"), subtitle: spell.subtitle,
                icon: spell.icon, keywords: spell.aliases.joined(separator: " ")
            ) { window.editor.cast(spell) }
        }
        let actions = [
            ("rewrite", String(localized: "Rewrite Selection")), ("shorten", String(localized: "Shorten Selection")),
            ("expand", String(localized: "Expand Selection")), ("explain", String(localized: "Explain Code")),
        ]
        items += actions.map { id, title in
            item("ai." + id, title, id == "explain" ? "" : "⌥⌘J", icon: "sparkles", keywords: "ai intelligence") {
                window.editor.runIntelligenceAction(id)
            }
        }
        #if DEBUG
        items.append(
            item("ai.test", String(localized: "Stream a Test Response"), "", icon: "sparkles", keywords: "debug ai") {
                window.streamTestResponse()
            })
        #endif
        return items
    }
}
