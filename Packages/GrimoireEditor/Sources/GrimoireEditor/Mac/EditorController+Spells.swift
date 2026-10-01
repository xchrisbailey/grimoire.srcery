#if os(macOS)
import AppKit
import GrimoireCore
import UniformTypeIdentifiers

/// An open Spells menu: where its `/` is, or, after the Code block spell, where the
/// language goes.
struct SpellSession {
    enum Mode: Equatable {
        case spells
        /// Picking a language; the code goes on the line starting at `codeLine`.
        case language(codeLine: Int)
        /// Picking the language to translate into, after the Translate spell at `trigger`.
        case translation(trigger: Range<Int>)
    }

    /// The `/` for spells, or the end of the opening fence for languages.
    var start: Int
    var mode: Mode

    /// True when nothing has been typed after the `/` yet and `offset` is right after it.
    func isFreshSpells(at offset: Int) -> Bool {
        mode == .spells && offset == start + 1
    }
}

/// The Spells menu: `/` at the start of a block or after a space opens it, typing filters
/// it, ↑↓ choose, ↵ or ⇥ cast, esc closes.
extension EditorController {
    private static let recentKey = "grimoire.recentSpells"

    var recentSpells: [String] {
        get { defaults.stringArray(forKey: Self.recentKey) ?? [] }
        set { defaults.set(Array(newValue.prefix(5)), forKey: Self.recentKey) }
    }

    // MARK: - Opening

    /// Whether a `/` at `offset` should open the menu: at a block's start or after
    /// whitespace, and not in frontmatter, code, HTML, tables, or a link or URL.
    func canCastSpell(at offset: Int) -> Bool {
        let text = textView.string as NSString
        guard offset < text.length, text.character(at: offset) == UInt16(UInt8(ascii: "/")),
            offset >= index.bodyStart || index.frontmatterRange == nil
        else { return false }
        if offset > 0 {
            let previous = text.character(at: offset - 1)
            guard previous == 32 || previous == 9 || previous == 10 || previous == 13 else { return false }
        }
        guard let position = index.blockIndex(at: offset) else { return true }
        switch index.blocks[position].kind {
        case .codeBlock, .html, .mdx, .table, .linkDefinitions: return false
        default: break
        }
        let source = index.sourceRange(of: position)
        guard source.contains(offset) else { return true }
        let relative = offset - source.lowerBound
        let spans = InlineScanner.scan(text.substring(with: NSRange(source)))
        return !spans.contains { span in
            switch span.kind {
            case .code, .autolink: span.range.contains(relative)
            case .link, .image: span.markers.last?.contains(relative) ?? false
            default: false
            }
        }
    }

    func openSpells(at offset: Int) {
        guard canCastSpell(at: offset) else { return }
        spellSession = SpellSession(start: offset, mode: .spells)
        spellsMenu.model.onChoose = { [weak self] position in self?.chooseSpell(position) }
        updateSpells()
    }

    // MARK: - Updating

    /// Refilters the menu from what's been typed since the `/`, or closes it when the
    /// typing has moved on.
    func updateSpells() {
        guard let session = spellSession else { return }
        let text = textView.string as NSString
        let caret = textView.selectedRange().location
        let queryStart = session.mode == .spells ? session.start + 1 : session.start
        guard caret >= queryStart, session.start < text.length || session.mode != .spells,
            session.mode != .spells || text.character(at: session.start) == UInt16(UInt8(ascii: "/"))
        else { return closeSpells() }
        let query = text.substring(with: NSRange(location: queryStart, length: caret - queryStart))
        guard query.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, query.count <= 24 else {
            return closeSpells()
        }
        let model = spellsMenu.model
        switch session.mode {
        case .spells:
            model.title = String(localized: "Spells")
            model.items = Spellbook.matching(query, in: availableSpells, recent: recentSpells).map {
                SpellsMenuModel.Item(id: $0.id, title: $0.title, subtitle: $0.subtitle, icon: $0.icon, hint: $0.hint)
            }
        case .translation:
            let lowered = query.lowercased()
            model.title = String(localized: "Translate into")
            model.items = Spellbook.translationLanguages
                .filter { lowered.isEmpty || $0.lowercased().hasPrefix(lowered) }
                .map { SpellsMenuModel.Item(id: $0, title: $0, subtitle: "", icon: nil, hint: "") }
        case .language:
            let lowered = query.lowercased()
            model.title = String(localized: "Language")
            model.items = Spellbook.languages
                .filter { lowered.isEmpty || $0.hasPrefix(lowered) || $0.contains(lowered) }
                .sorted { ($0.hasPrefix(lowered) ? 0 : 1) < ($1.hasPrefix(lowered) ? 0 : 1) }
                .map { SpellsMenuModel.Item(id: $0, title: $0, subtitle: "", icon: nil, hint: "") }
        }
        model.selected = 0
        showSpellsMenu(anchor: session.start)
        spellsMenu.announceSelection()
    }

    private func showSpellsMenu(anchor: Int) {
        guard let window = textView.window else { return }
        let rect = textView.firstRect(forCharacterRange: NSRange(location: anchor, length: 0), actualRange: nil)
        spellsMenu.show(at: rect, in: window)
    }

    func closeSpells() {
        spellSession = nil
        spellsMenu.close()
    }

    func closeSpellsIfCaretLeft() {
        guard let session = spellSession else { return }
        let selection = textView.selectedRange()
        let end = session.start + 1 + 24
        if selection.length > 0 || selection.location < session.start || selection.location > end {
            closeSpells()
        }
    }

    // MARK: - Keys

    func handleSpellsCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            spellsMenu.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            spellsMenu.moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            guard !spellsMenu.model.items.isEmpty else {
                closeSpells()
                return false
            }
            chooseSpell(spellsMenu.model.selected)
        case #selector(NSResponder.cancelOperation(_:)):
            if case .language(let codeLine) = spellSession?.mode {
                let typed = textView.selectedRange().location - (spellSession?.start ?? 0)
                closeSpells()
                textView.setSelectedRange(NSRange(location: codeLine + max(0, typed), length: 0))
            } else {
                closeSpells()
            }
        default:
            return false
        }
        return true
    }

    // MARK: - Casting

    func chooseSpell(_ position: Int) {
        guard let session = spellSession, spellsMenu.model.items.indices.contains(position) else { return }
        let item = spellsMenu.model.items[position]
        let caret = textView.selectedRange().location
        closeSpells()
        switch session.mode {
        case .spells:
            guard let spell = availableSpells.first(where: { $0.id == item.id }) else { return }
            if spell.effect == .intelligence {
                castIntelligence(spell, trigger: session.start..<caret)
            } else {
                cast(spell, trigger: session.start..<caret)
            }
        case .translation(let trigger):
            castIntelligence(named: "translate", trigger: trigger.lowerBound..<caret, language: item.id)
        case .language(let codeLine):
            // `codeLine` was measured before any language was typed, so the code line now
            // starts the language's length after it.
            let target = codeLine + item.id.utf16.count
            apply(TextEdit(range: session.start..<caret, replacement: item.id, selection: target..<target))
        }
    }

    func cast(_ spell: Spell, trigger: Range<Int>) {
        let result = SpellCaster(text: textView.string, trigger: trigger).cast(spell)
        apply(result.edit, actionName: String(localized: "Cast \(spell.title)"))
        recentSpells = [spell.id] + recentSpells.filter { $0 != spell.id }
        switch result.followUp {
        case .none:
            break
        case .pickLanguage(let fenceEnd, let codeLine):
            spellSession = SpellSession(start: fenceEnd, mode: .language(codeLine: codeLine))
            spellsMenu.model.onChoose = { [weak self] position in self?.chooseSpell(position) }
            updateSpells()
        case .pickImage(let offset):
            pickImage(insertingAt: offset)
        }
    }

    private func pickImage(insertingAt offset: Int) {
        guard let assets = assetsFolder else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url, let copy = try? copyIntoAssets(file, assets: assets)
        else { return }
        let markdown = imageLink(copy)
        let end = offset + markdown.utf16.count
        apply(TextEdit(range: offset..<offset, replacement: markdown, selection: end..<end))
    }
}
#endif
