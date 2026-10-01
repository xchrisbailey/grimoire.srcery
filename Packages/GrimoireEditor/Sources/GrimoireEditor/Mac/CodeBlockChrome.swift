#if os(macOS)
import AppKit
import GrimoireCore

/// The language and Copy buttons at the top right of a fenced code block, shown while the
/// pointer is over the block or the caret is in it (Preview only).
@MainActor
final class CodeBlockChrome: NSObject {
    private weak var controller: EditorController?
    private let container = NSView()
    private let languageButton = NSButton()
    private let copyButton = NSButton()
    /// The block the chrome sits on.
    private(set) var block: Int?
    private var hovered: Int?
    /// Where Copy puts the code.
    var pasteboard = NSPasteboard.general
    var isVisible: Bool { !container.isHidden }
    var languageTitle: String { languageButton.attributedTitle.string }

    init(controller: EditorController) {
        self.controller = controller
        super.init()
        container.isHidden = true
        container.wantsLayer = true
        for button in [languageButton, copyButton] {
            button.isBordered = false
            button.target = self
            button.setButtonType(.momentaryChange)
            container.addSubview(button)
        }
        languageButton.action = #selector(chooseLanguage)
        copyButton.action = #selector(copyCode)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "Copy"))
        copyButton.toolTip = String(localized: "Copy")
        controller.textView.addSubview(container)
        applyTheme(controller.styler.theme)
    }

    func applyTheme(_ theme: EditorTheme) {
        copyButton.contentTintColor = theme.faint
        languageButton.contentTintColor = theme.faint
        updateLanguageTitle()
    }

    // MARK: - Showing

    /// The pointer moved over the text; `nil` when it left.
    func pointerMoved(toBlock position: Int?) {
        hovered = position
        update()
    }

    /// Places the chrome on the hovered block, else the caret's, if it's fenced code.
    func update() {
        guard let controller, controller.mode == .preview else { return hide() }
        let caretBlock = controller.index.blockIndex(at: controller.textView.selectedRange().location)
        let target = [hovered, caretBlock].compactMap { $0 }.first { isFencedCode($0) }
        guard let target, let frame = controller.blockHandle.firstLineFrame(of: target) else { return hide() }
        block = target
        updateLanguageTitle()
        layout(on: frame)
        container.isHidden = false
    }

    func hide() {
        container.isHidden = true
        block = nil
    }

    private func isFencedCode(_ position: Int) -> Bool {
        guard let controller, position < controller.index.blocks.count,
            case .codeBlock = controller.index.blocks[position].kind
        else { return false }
        return MarkdownSyntax.isFenced(controller.index.blocks[position].source)
    }

    private func layout(on firstLine: CGRect) {
        guard let textView = controller?.textView else { return }
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        let columnRight = textView.textContainerOrigin.x + (textView.textContainer?.size.width ?? 0) - padding
        languageButton.sizeToFit()
        let height: CGFloat = 20
        let copySize = CGSize(width: 22, height: height)
        let languageSize = CGSize(width: languageButton.frame.width + 8, height: height)
        let width = languageSize.width + copySize.width + 4
        container.frame = CGRect(
            x: columnRight - width - 8, y: firstLine.minY + (firstLine.height - height) / 2, width: width,
            height: height)
        languageButton.frame = CGRect(origin: .zero, size: languageSize)
        copyButton.frame = CGRect(origin: CGPoint(x: languageSize.width + 4, y: 0), size: copySize)
    }

    private var language: String? {
        guard let controller, let block, block < controller.index.blocks.count,
            case .codeBlock(let language) = controller.index.blocks[block].kind
        else { return nil }
        return language
    }

    private func updateLanguageTitle() {
        guard let theme = controller?.styler.theme else { return }
        let title = (language ?? String(localized: "Plain text")) + " ⌄"
        languageButton.attributedTitle = NSAttributedString(
            string: title, attributes: [.font: theme.metadata, .foregroundColor: theme.faint])
        languageButton.toolTip = String(localized: "Language")
    }

    // MARK: - Actions

    @objc private func chooseLanguage() {
        let menu = NSMenu()
        let current = language?.lowercased()
        let plain = MenuClosure.item(String(localized: "Plain text")) { [weak self] in self?.setLanguage(nil) }
        plain.state = current == nil ? .on : .off
        menu.addItem(plain)
        menu.addItem(.separator())
        for name in Spellbook.languages where name != "text" {
            let item = MenuClosure.item(name) { [weak self] in self?.setLanguage(name) }
            item.state = current == name ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: languageButton.bounds.maxY + 4), in: languageButton)
    }

    /// Rewrites the opening fence's info string.
    func setLanguage(_ name: String?) {
        guard let controller, let block else { return }
        let start = controller.index.sourceRange(of: block).lowerBound
        let source = controller.index.blocks[block].source
        let fenceLine = source.prefix { !$0.isNewline }
        let indent = fenceLine.prefix { $0 == " " }
        let fence = fenceLine.dropFirst(indent.count).prefix { $0 == "`" || $0 == "~" }
        let replacement = String(indent) + String(fence) + (name ?? "")
        let lineLength = fenceLine.utf16.count
        let caret = controller.textView.selectedRange()
        let shift = replacement.utf16.count - lineLength
        let newCaret = caret.location > start + lineLength ? caret.location + shift : min(caret.location, start)
        controller.apply(
            TextEdit(range: start..<(start + lineLength), replacement: replacement, selection: newCaret..<newCaret),
            actionName: String(localized: "Change Language"))
        update()
    }

    @objc func copyCode() {
        guard let controller, let block else { return }
        let text = controller.textView.string as NSString
        let range = NSRange(controller.index.sourceRange(of: block))
        guard let body = controller.styler.codeBody(of: range, in: text) else { return }
        pasteboard.clearContents()
        pasteboard.setString(text.substring(with: body), forType: .string)
        copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: String(localized: "Copied"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.image = NSImage(
                systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "Copy"))
        }
    }
}
#endif
