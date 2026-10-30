#if os(macOS)
import AppKit
import GrimoireCore
import Testing

@testable import GrimoireEditor

/// The windows the editors live in, kept for the whole run so hosting never changes mid-test.
@MainActor private var windows: [NSWindow] = []

final class EditorTestDefaults: UserDefaults, @unchecked Sendable {
    let suiteName: String

    init() {
        suiteName = "grimoire-tests-\(UUID())"
        super.init(suiteName: suiteName)!
    }
}

final class EditorTestPreferences: @unchecked Sendable {
    private let lock = NSLock()
    private var suites: [String] = []

    func register(_ defaults: EditorTestDefaults) {
        lock.withLock { suites.append(defaults.suiteName) }
    }

    func cleanUp() {
        // Editors can outlive their test through AppKit; teardown owns only this scope's UUID domains.
        for suite in lock.withLock({ suites }) {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }
}

enum EditorTestContext {
    @TaskLocal static var preferences: EditorTestPreferences?
}

nonisolated(nonsending) func withEditorFixtures<Result: Sendable>(
    _ body: () async throws -> Result
) async rethrows -> Result {
    let preferences = EditorTestPreferences()
    defer { preferences.cleanUp() }
    return try await EditorTestContext.$preferences.withValue(preferences) { try await body() }
}

struct EditorFixtureScope: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        try await withEditorFixtures(function)
    }
}

/// An editor hosted in a window, as in the app, with the repo's fonts registered.
@MainActor func makeEditor(
    _ text: String = "", height: CGFloat = 700, width: CGFloat = 900, dark: Bool = false,
    mode: EditorMode = .preview, caret: Int? = nil, synchronousHighlighting: Bool = true,
    freshDefaults: Bool = false
) -> EditorController {
    BrandFontTests.registerRepoFonts()
    let controller = EditorController()
    if freshDefaults {
        guard let preferences = EditorTestContext.preferences else {
            preconditionFailure("Fresh editor defaults require EditorFixtureScope")
        }
        let defaults = EditorTestDefaults()
        preferences.register(defaults)
        controller.defaults = defaults
    }
    controller.styler.highlightsSynchronously = synchronousHighlighting
    controller.mode = mode
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered,
        defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    controller.scrollView.frame = window.contentView?.bounds ?? .zero
    window.contentView?.addSubview(controller.scrollView)
    // Match MarkdownEditor.makeNSView: an initially dark view need not receive an appearance change.
    controller.styler.theme.isDark = controller.textView.isDarkAppearance
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
