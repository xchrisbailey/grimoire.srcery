import AppKit
import GrimoireCore

/// A published file is never created again just because opening its editor was deferred.
struct DeferredDocument {
    var url: URL
    let caretUTF16: Int?
    let identity: any NSObjectProtocol
}

extension WindowState {
    func prepareForRelease() -> Bool {
        guard save() else {
            if let error = document?.saveError { actions.error = error }
            bringToFront()
            return false
        }
        guard deferredDocuments.isEmpty else {
            if let openError { actions.error = openError }
            return false
        }
        return true
    }

    func prepareWindowClose() -> Bool {
        guard prepareForRelease() else { return false }
        resumePublishedDocuments()
        return deferredDocuments.isEmpty && prepareForRelease()
    }

    func retryRecovery() {
        workspace?.reconcileLifecycleOperations()
        actions.error = workspace?.lastError
        if save() { resumePublishedDocuments() }
    }

    func deferPublishedDocument(_ created: PublishedDocument) {
        do {
            guard
                let identity = try created.url.resourceValues(forKeys: [.fileResourceIdentifierKey])
                    .fileResourceIdentifier
            else { throw CreatedDocumentOpenError(url: created.url) }
            deferredDocuments.append(
                DeferredDocument(
                    url: created.url, caretUTF16: created.editorCaretUTF16,
                    identity: identity))
        } catch { openError = error }
    }

    func resumePublishedDocuments() {
        while let pending = deferredDocuments.first {
            do {
                let current = try pending.url.resourceValues(forKeys: [.fileResourceIdentifierKey])
                    .fileResourceIdentifier
                guard current?.isEqual(pending.identity) == true else {
                    throw CreatedDocumentOpenError(url: pending.url)
                }
                guard select(pending.url, initialEditorMode: pending.caretUTF16 == nil ? nil : .raw),
                    document?.url == pending.url
                else { return }
                deferredDocuments.removeFirst()
                if let caret = pending.caretUTF16 {
                    editor.revealWhenReady(NSRange(location: caret, length: 0), in: pending.url)
                }
            } catch {
                openError = error
                return
            }
        }
    }

    func moveDeferredDocuments(from: URL, to: URL) {
        let prefix = from.standardizedFileURL.path + "/"
        for index in deferredDocuments.indices {
            let path = deferredDocuments[index].url.standardizedFileURL.path
            if path == from.standardizedFileURL.path {
                deferredDocuments[index].url = to
            } else if path.hasPrefix(prefix) {
                deferredDocuments[index].url = to.appending(path: String(path.dropFirst(prefix.count)))
            }
        }
    }

    func attach(to host: NSWindow?) {
        guard let host else { return }
        hostWindow = host
        if let closeBridge, host.delegate === closeBridge { return }
        let bridge = WindowCloseBridge(state: self, forwarding: host.delegate)
        closeBridge = bridge
        host.delegate = bridge
    }
}

/// SwiftUI still receives its delegate callbacks; only the release decision is interposed.
@MainActor final class WindowCloseBridge: NSObject, NSWindowDelegate {
    private weak var state: WindowState?
    private let original: (any NSWindowDelegate)?

    init(state: WindowState, forwarding original: (any NSWindowDelegate)?) {
        self.state = state
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard state?.prepareWindowClose() ?? true else { return false }
        return original?.windowShouldClose?(sender) ?? true
    }

    func windowWillClose(_ notification: Notification) {
        if let state {
            state.presentationID = nil
            state.hostWindow = nil
            state.close()
        }
        original?.windowWillClose?(notification)
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        MainActor.assumeIsolated {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }
}
