#if os(macOS)
import AppKit
import GrimoireCore

/// Tables in the editor: Tab and Enter move between cells, the context menu adds and
/// removes rows and columns, pasted spreadsheet cells become a table, and leaving a table
/// re-pads its pipes.
extension EditorController {
    /// Tab, Shift-Tab and Enter inside a table. Nil for keys tables don't change.
    func handleTableCommand(_ selector: Selector) -> Bool? {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            return perform(editing.moveToNextCell(backward: false), actionName: String(localized: "Next Cell"))
        case #selector(NSResponder.insertBacktab(_:)):
            return perform(editing.moveToNextCell(backward: true), actionName: String(localized: "Previous Cell"))
        case #selector(NSResponder.insertNewline(_:)):
            // A table row can't hold a line break, so Shift-Enter does nothing.
            if shift { return true }
            return perform(editing.tableNewline(), actionName: String(localized: "Next Row"))
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), #selector(NSResponder.insertLineBreak(_:)):
            return true
        default:
            return nil
        }
    }

    /// Re-pads the table with block id `id`, if it's still there.
    func formatTable(id: Block.ID) {
        guard let position = index.blocks.firstIndex(where: { $0.id == id }),
            let edit = editing.formatTable(block: position)
        else { return }
        apply(edit)
    }

    func changeTable(_ change: BlockEditing.TableChange, actionName: String) {
        perform(editing.changeTable(change), actionName: actionName)
    }

    /// Adds table commands to the text view's context menu when the click is in a table.
    func tableMenuItems(at offset: Int) -> [NSMenuItem] {
        guard let position = index.blockIndex(at: offset), index.blocks[position].kind == .table else { return [] }
        let selection = textView.selectedRange()
        if !NSLocationInRange(offset, selection) { textView.setSelectedRange(NSRange(location: offset, length: 0)) }
        var items: [NSMenuItem] = []
        func add(_ title: String, _ action: @escaping () -> Void) {
            items.append(MenuClosure.item(title, action))
        }
        if mode == .preview {
            add(String(localized: "Insert Row Above")) { [weak self] in
                self?.changeTable(.insertRowAbove, actionName: String(localized: "Insert Row"))
            }
            add(String(localized: "Insert Row Below")) { [weak self] in
                self?.changeTable(.insertRowBelow, actionName: String(localized: "Insert Row"))
            }
            add(String(localized: "Insert Column Left")) { [weak self] in
                self?.changeTable(.insertColumnLeft, actionName: String(localized: "Insert Column"))
            }
            add(String(localized: "Insert Column Right")) { [weak self] in
                self?.changeTable(.insertColumnRight, actionName: String(localized: "Insert Column"))
            }
            items.append(.separator())
            add(String(localized: "Delete Row")) { [weak self] in
                self?.changeTable(.deleteRow, actionName: String(localized: "Delete Row"))
            }
            add(String(localized: "Delete Column")) { [weak self] in
                self?.changeTable(.deleteColumn, actionName: String(localized: "Delete Column"))
            }
            items.append(.separator())
            let align = NSMenuItem(title: String(localized: "Align Column"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let alignments: [(String, MarkdownTable.Alignment)] = [
                (String(localized: "Left"), .left), (String(localized: "Center"), .center),
                (String(localized: "Right"), .right),
            ]
            for (title, alignment) in alignments {
                submenu.addItem(
                    MenuClosure.item(title) { [weak self] in
                        self?.changeTable(.align(alignment), actionName: String(localized: "Align Column"))
                    })
            }
            align.submenu = submenu
            items.append(align)
        }
        add(String(localized: "Format Table")) { [weak self] in
            guard let self else { return }
            self.perform(self.editing.formatTable(), actionName: String(localized: "Format Table"))
        }
        items.append(.separator())
        return items
    }

    /// Cells copied from Numbers, Excel or Sheets (tab-separated), or CSV, as a table.
    func tableMarkdown(from pasteboard: NSPasteboard) -> String? {
        guard editing.tableCell == nil else { return nil }
        let csvType = NSPasteboard.PasteboardType("public.comma-separated-values-text")
        if let csv = pasteboard.string(forType: csvType), let table = MarkdownTable(delimited: csv, csv: true) {
            return table.markdown
        }
        guard let string = pasteboard.string(forType: .string), string.contains("\t"),
            let table = MarkdownTable(delimited: string)
        else { return nil }
        return table.markdown
    }

    /// Puts a block on its own lines at the caret, with blank lines around it.
    func insertBlock(_ markdown: String, actionName: String) {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let lineIsBlank = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let before = selection.location == 0 || (lineIsBlank && line.location == selection.location) ? "" : "\n\n"
        let afterLocation = NSMaxRange(selection)
        let after = afterLocation >= text.length ? "\n" : "\n\n"
        let replacement = before + markdown + after
        let end = selection.location + before.utf16.count + markdown.utf16.count
        apply(
            TextEdit(range: selection.location..<afterLocation, replacement: replacement, selection: end..<end),
            actionName: actionName)
    }
}

/// A menu item that runs a closure.
final class MenuClosure: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func run() { action() }

    static func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let target = MenuClosure(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        return item
    }
}
#endif
