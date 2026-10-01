import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Mirrors the document's unsaved state onto the window, so the close button shows the
/// standard edited dot.
struct DocumentEditedMarker: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let isEdited = isEdited
        DispatchQueue.main.async { view.window?.isDocumentEdited = isEdited }
    }
}

/// The dot in the toolbar: peach while there are unsaved edits, quiet once they're saved.
struct InkDot: View {
    let isWet: Bool

    var body: some View {
        Circle()
            .fill(isWet ? Color.brand(\.caret) : Color.brand(\.overlay0).opacity(0.5))
            .frame(width: 7, height: 7)
            .help(isWet ? Text("Ink still wet") : Text("Ink dry"))
            .accessibilityLabel(isWet ? Text("Ink still wet") : Text("Ink dry"))
            .padding(.horizontal, 4)
    }
}

/// Preview | Raw, at the trailing end of the title bar.
struct ModePicker: View {
    @Binding var mode: EditorMode

    var body: some View {
        Picker(selection: $mode) {
            Text("Preview").tag(EditorMode.preview)
            Text("Raw").tag(EditorMode.raw)
        } label: {
            Text("Mode")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help(Text("Switch between the styled page and its markdown source (⇧⌘R)"))
    }
}

/// In focus mode the title bar goes transparent and its buttons fade until the pointer
/// comes near them.
struct FocusChrome: NSViewRepresentable {
    let isFocused: Bool

    func makeNSView(context: Context) -> FocusChromeView { FocusChromeView() }

    func updateNSView(_ view: FocusChromeView, context: Context) {
        view.isFocused = isFocused
    }
}

final class FocusChromeView: NSView {
    var isFocused = false {
        didSet { if isFocused != oldValue { apply() } }
    }
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private var buttons: [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
    }

    private func apply() {
        guard let window else { return }
        window.titlebarAppearsTransparent = isFocused
        window.titleVisibility = isFocused ? .hidden : .visible
        setButtonsVisible(!isFocused)
        if isFocused, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.revealNearTop(event)
                return event
            }
            window.acceptsMouseMovedEvents = true
        } else if !isFocused, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func revealNearTop(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let nearTop = event.locationInWindow.y > window.frame.height - 44
        setButtonsVisible(nearTop)
    }

    private func setButtonsVisible(_ visible: Bool) {
        let alpha: CGFloat = visible ? 1 : 0.25
        guard buttons.first?.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for button in buttons { button.animator().alphaValue = alpha }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
