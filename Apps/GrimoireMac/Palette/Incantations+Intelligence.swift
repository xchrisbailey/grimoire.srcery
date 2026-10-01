import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

extension Incantations {
    /// AI commands, offered only when the model can run for this project.
    static func intelligence(_ window: WindowState) -> [PaletteItem] {
        guard window.intelligenceReady else { return [] }
        var items: [PaletteItem] = []
        #if DEBUG
        items.append(
            item("ai.test", String(localized: "Stream a Test Response"), "", icon: "sparkles", keywords: "debug ai") {
                window.streamTestResponse()
            })
        #endif
        return items
    }
}
