import AppKit
import GrimoireCore

/// The alerts shown when a document can't be saved and the window or app wants to let go of it.
/// They run modally because the callers (closing a window, quitting) need the answer at once.
@MainActor enum DiscardPrompt {
    enum Choice { case keepEditing, discard }

    static func ask(about refusal: ReleaseRefusal, name: String) -> Choice {
        let detail: String
        switch refusal {
        case .conflict:
            detail = String(
                localized:
                    """
                    \(name) changed on disk while you were editing, so Grimoire hasn't saved your changes. \
                    Keep Editing to choose Keep Mine or Load Theirs.
                    """)
        case .saveFailed(let error):
            detail =
                saveFailureMessage(error, name: name) + "\n"
                + String(localized: "Keep Editing to try again.")
        }
        return run(
            title: String(localized: "Your changes to \(name) haven't been saved."),
            detail: detail + "\n\n"
                + String(
                    localized:
                        """
                        If you discard them, Grimoire keeps a copy first. Reopen the file and choose \
                        Browse Versions… to get it back. The file itself isn't touched.
                        """),
            destructive: false)
    }

    /// Asked when no copy could be kept, so discarding would lose the changes for good.
    static func confirmLoss(name: String) -> Choice {
        run(
            title: String(localized: "Grimoire couldn't keep a copy of your changes to \(name)."),
            detail: String(
                localized:
                    "If you discard them now, they will be lost. The file itself isn't touched."),
            destructive: true)
    }

    private static func run(title: String, detail: String, destructive: Bool) -> Choice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        // The first button is the default, so Return keeps the changes.
        alert.addButton(withTitle: String(localized: "Keep Editing"))
        let discard = alert.addButton(withTitle: String(localized: "Discard Changes and Close"))
        discard.hasDestructiveAction = destructive
        // A quit from the Dock can arrive while another app is in front.
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .discard : .keepEditing
    }
}
