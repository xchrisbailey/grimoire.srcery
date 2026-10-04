#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

/// The windows the editors live in, kept for the whole run so hosting never changes mid-test.
@MainActor private var windows: [NSWindow] = []

/// An editor hosted in a window, as in the app, with the repo's fonts registered.
@MainActor func makeEditor(
    _ text: String = "", height: CGFloat = 700, width: CGFloat = 900, dark: Bool = false,
    mode: EditorMode = .preview, caret: Int? = nil, synchronousHighlighting: Bool = true,
    freshDefaults: Bool = false
) -> EditorController {
    BrandFontTests.registerRepoFonts()
    let controller = EditorController()
    if freshDefaults {
        controller.defaults = UserDefaults(suiteName: "grimoire-tests-\(UUID())") ?? .standard
    }
    controller.styler.highlightsSynchronously = synchronousHighlighting
    controller.mode = mode
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered,
        defer: false)
    if dark { window.appearance = NSAppearance(named: .darkAqua) }
    controller.scrollView.frame = window.contentView?.bounds ?? .zero
    window.contentView?.addSubview(controller.scrollView)
    controller.load(text, flavor: .markdown)
    if let caret { controller.textView.setSelectedRange(NSRange(location: caret, length: 0)) }
    window.displayIfNeeded()
    windows.append(window)
    return controller
}

extension EditorController {
    func font(at offset: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont
    }

    func color(at offset: Int) -> PaletteColor? {
        guard
            let color = textView.textStorage?.attribute(.foregroundColor, at: offset, effectiveRange: nil)
                as? NSColor
        else { return nil }
        var resolved: NSColor?
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        guard let resolved else { return nil }
        return PaletteColor(
            red: UInt8((resolved.redComponent * 255).rounded()),
            green: UInt8((resolved.greenComponent * 255).rounded()),
            blue: UInt8((resolved.blueComponent * 255).rounded()))
    }

    func type(_ string: String) {
        for character in string {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
    }

    /// Types as the keyboard does, so auto-pairing sees it.
    func typeKeys(_ string: String) {
        for character in string {
            textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    func press(_ selector: Selector) {
        textView.doCommand(by: selector)
    }
}

func keyEvent(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}
#endif
