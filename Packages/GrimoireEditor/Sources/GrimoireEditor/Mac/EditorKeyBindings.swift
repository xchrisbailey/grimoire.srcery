#if os(macOS)
import AppKit
import GrimoireCore

/// The shortcuts the editor handles itself rather than through a menu. Nil turns one
/// off.
public struct EditorKeyBindings: Equatable, Sendable {
    public var toggleTask: KeyCombo? = ShortcutAction.toggleTask.defaultCombo
    public var duplicateBlock: KeyCombo? = ShortcutAction.duplicateBlock.defaultCombo
    /// Rewrite, shorten or expand the selection.
    public var writingTools: KeyCombo? = ShortcutAction.writingTools.defaultCombo

    public init() {}

    public init(toggleTask: KeyCombo?, duplicateBlock: KeyCombo?, writingTools: KeyCombo?) {
        self.toggleTask = toggleTask
        self.duplicateBlock = duplicateBlock
        self.writingTools = writingTools
    }
}

extension KeyCombo {
    /// The combo a key press makes, or nil for keys a shortcut can't use.
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let named: [UInt16: Named] = [
            36: .return, 76: .return, 48: .tab, 49: .space, 51: .delete, 117: .forwardDelete, 53: .escape,
            126: .upArrow, 125: .downArrow, 123: .leftArrow, 124: .rightArrow,
        ]
        if let key = named[event.keyCode] {
            self.init(key, modifiers)
            return
        }
        // The key's own character, as if no modifier were held: ⇧⌘D is "d" with ⇧.
        guard let character = event.characters(byApplyingModifiers: [])?.lowercased(), character.count == 1,
            let scalar = character.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        self.init(character, modifiers)
    }
}
#endif
