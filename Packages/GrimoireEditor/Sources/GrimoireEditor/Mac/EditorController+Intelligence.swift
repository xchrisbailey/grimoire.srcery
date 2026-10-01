#if os(macOS)
import AppKit
import GrimoireCore

/// The AI spells and selection actions (#19): the editor works out what each reads and where
/// its result goes, and the app runs the model and streams the result back in.
extension EditorController {
    /// Spells on offer: the standard ones, plus the AI spells when the model can run.
    var availableSpells: [Spell] {
        Spellbook.standard + (intelligenceEnabled ? Spellbook.intelligence : [])
    }

    func castIntelligence(_ spell: Spell, trigger: Range<Int>) {
        recentSpells = [spell.id] + recentSpells.filter { $0 != spell.id }
        if spell.id == "translate" {
            // Ask which language first; what's typed after the spell filters the list.
            spellSession = SpellSession(start: trigger.upperBound, mode: .translation(trigger: trigger))
            spellsMenu.model.onChoose = { [weak self] position in self?.chooseSpell(position) }
            updateSpells()
            return
        }
        castIntelligence(named: spell.id, trigger: trigger)
    }

    public func castIntelligence(named command: String, trigger: Range<Int>, language: String? = nil) {
        let plan = IntelligencePlanner(text: textView.string, index: index)
            .plan(command, trigger: trigger, language: language)
        onIntelligence?(plan)
    }

    /// Runs a selection action: rewrite, shorten, expand or explain.
    public func runIntelligenceAction(_ action: String) {
        guard
            let plan = IntelligencePlanner(text: textView.string, index: index)
                .plan(action: action, selection: textView.selectedRange())
        else { return NSSound.beep() }
        onIntelligence?(plan)
    }

    /// The actions that make sense for the selection, as menu items.
    func intelligenceMenuItems() -> [NSMenuItem] {
        guard intelligenceEnabled else { return [] }
        let selection = textView.selectedRange()
        var items: [NSMenuItem] = []
        if selection.length > 0 {
            let actions = [
                ("rewrite", String(localized: "Rewrite")), ("shorten", String(localized: "Shorten")),
                ("expand", String(localized: "Expand")),
            ]
            for (id, title) in actions {
                items.append(MenuClosure.item(title) { [weak self] in self?.runIntelligenceAction(id) })
            }
        }
        if let position = index.blockIndex(at: selection.location), case .codeBlock = index.blocks[position].kind {
            items.append(
                MenuClosure.item(String(localized: "Explain Code")) { [weak self] in
                    self?.runIntelligenceAction("explain")
                })
        }
        return items
    }

    /// ⌥⌘J: the selection actions in a menu at the selection.
    func showIntelligenceMenu() -> Bool {
        let items = intelligenceMenuItems()
        guard !items.isEmpty else { return false }
        let menu = NSMenu()
        for item in items { menu.addItem(item) }
        let selection = textView.selectedRange()
        let screen = textView.firstRect(
            forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
        guard let window = textView.window else { return false }
        let point = textView.convert(window.convertFromScreen(screen).origin, from: nil)
        menu.popUp(positioning: nil, at: CGPoint(x: point.x, y: point.y + 4), in: textView)
        return true
    }
}
#endif
