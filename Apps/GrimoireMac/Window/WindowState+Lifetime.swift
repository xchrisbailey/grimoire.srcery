import AppKit
import GrimoireCore

/// A published file is never created again just because opening its editor was deferred.
struct DeferredDocument {
    var url: URL
    let publication: PublishedDocument
}

struct CreatedDocumentsOpenError: LocalizedError {
    let failures: [CreatedDocumentOpenError]
    var errorDescription: String? {
        failures.compactMap(\.errorDescription).joined(separator: "\n\n")
    }
}

extension WindowState {
    func configureDestructiveActions() {
        actions.didUnbind = { [weak self] in
            guard let self else { return }
            ExternalOpens.shared.rootsRemoved(in: projectID)
        }
        actions.willPerformDestructiveOperation = { [weak self] plan in
            guard let self else { return false }
            return ExternalOpens.shared.prepareDestructiveOperation(plan, in: projectID)
        }
    }

    func prepareProjectDeletion() -> Bool {
        // Publication handoffs are resolved separately, without changing selection during a staged deletion.
        guard deferredDocuments.isEmpty else { return false }
        guard document?.save() ?? true else {
            if let error = document?.saveError { actions.error = error }
            bringToFront()
            return false
        }
        return true
    }

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
        prepareForRelease()
    }

    func retryRecovery() {
        workspace?.reconcileLifecycleOperations()
        actions.error = workspace?.lastError
        save()
    }

    func deferPublishedDocument(_ created: PublishedDocument) {
        guard receivedPublications.insert(created.id).inserted else { return }
        deferredDocuments.append(DeferredDocument(url: created.url, publication: created))
    }

    func resumePublishedDocuments() {
        var failures: [CreatedDocumentOpenError] = []
        defer {
            if failures.count == 1 {
                actions.error = failures.first
            } else if !failures.isEmpty {
                actions.error = CreatedDocumentsOpenError(failures: failures)
            }
        }
        while let pending = deferredDocuments.first {
            do {
                guard try pending.publication.matchesPublishedItem(at: pending.url) else {
                    throw CreatedDocumentOpenError(url: pending.url)
                }
                guard select(pending.url, initialEditorMode: pending.publication.editorCaretUTF16 == nil ? nil : .raw),
                    document?.url == pending.url
                else { return }
                deferredDocuments.removeFirst()
                if let caret = pending.publication.editorCaretUTF16 {
                    editor.revealWhenReady(NSRange(location: caret, length: 0), in: pending.url)
                }
            } catch {
                // Missing/replaced publications are terminal handoff failures, not dirty buffers.
                // Drain them without opening replacements, while leaving retryable handoffs queued.
                if error is CreatedDocumentOpenError || Self.isMissingPublishedFile(error) {
                    deferredDocuments.removeFirst()
                    failures.append(CreatedDocumentOpenError(url: pending.url))
                    continue
                }
                openError = error
                return
            }
        }
    }

    private static func isMissingPublishedFile(_ error: any Error) -> Bool {
        if let error = error as? POSIXError { return error.code == .ENOENT || error.code == .ENOTDIR }
        guard let error = error as? CocoaError else { return false }
        return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
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
