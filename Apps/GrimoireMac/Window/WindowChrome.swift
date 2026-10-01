import AppKit
import GrimoireCore
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
