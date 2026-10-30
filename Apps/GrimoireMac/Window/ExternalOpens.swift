import AppKit
import GrimoireCore
import SwiftUI

/// Receives the files Finder and the Dock hand over, and finds a window for each.
///
/// A file opens in the window that already shows its project. A project no window shows
/// waits in `pending` until a new window takes it, so the window never shows a restored
/// file first. A window showing another project is never taken over.
@MainActor
final class ExternalOpens {
    static let shared = ExternalOpens()

    /// The one library of the app, since files can arrive before any window exists.
    let library = ProjectLibrary()
    /// Opens a new project window. Set by the first window to appear.
    var openWindow: (() -> Void)?

    /// Finder's files arrive after the first windows appear but before launching ends, so
    /// windows hold off restoring until then.
    private var hasLaunched = false
    private var afterLaunch: [() -> Void] = []
    private var windows: [WeakWindow] = []
    private var pending = PendingOpens()
    private var blockedWindows: [WindowState] = []
    private var preparingDeletion = false

    private struct WeakWindow {
        weak var window: WindowState?
    }

    /// Runs `work` once the app has finished launching, and at once if it has.
    func whenLaunched(_ work: @escaping () -> Void) {
        if hasLaunched { work() } else { afterLaunch.append(work) }
    }

    func finishLaunching() {
        hasLaunched = true
        let waiting = afterLaunch
        afterLaunch = []
        for work in waiting { work() }
        requestWindows()
    }

    func open(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL && !$0.hasDirectoryPath }
        library.lastError = nil
        let placements = pending.place(files, in: library, unsortedName: String(localized: "Unsorted"))
        if let error = library.lastError {
            library.lastError = nil
            report(error)
        }
        for placement in placements {
            if let window = windowShowing(placement.projectID) {
                window.open(placement.urls)
                window.bringToFront()
            } else {
                pending.add(placement)
            }
        }
        NSApp.activate()
        requestWindows()
    }

    func retryLibraryLoad() {
        library.retryLoad()
        guard library.loadError == nil else { return }
        open([])
    }

    /// Tells the user a file couldn't be opened: in a window's alert, or on its own when
    /// the app has none yet.
    private func report(_ error: Error) {
        if let window = windows.compactMap(\.window).first {
            window.actions.error = error
        } else {
            Task { NSAlert(error: error).runModal() }
        }
    }

    /// A window that is about to restore itself asks what Finder left for it: the files of
    /// the project it showed last time, or, for a new window, those of any project waiting.
    func claim(preferring project: Project.ID?, isNew: Bool) -> ProjectLibrary.Placement? {
        pending.claim(preferring: project, isNew: isNew)
    }

    /// Windows show their project through this once restored, and are found by it until
    /// they go.
    func register(_ window: WindowState) {
        windows.removeAll { $0.window == nil }
        if !windows.contains(where: { $0.window === window }) { windows.append(WeakWindow(window: window)) }
        requestWindows()
    }

    func unregister(_ window: WindowState) {
        windows.removeAll { $0.window == nil || $0.window === window }
        blockedWindows.removeAll { $0 === window }
    }

    func retainBlocked(_ window: WindowState) {
        guard !blockedWindows.contains(where: { $0 === window }) else { return }
        blockedWindows.append(window)
        window.hostWindow = nil
        // Direct native close can bypass the veto. Rehome the exact state, not disk text.
        openWindow?()
    }

    func reclaimBlocked() -> WindowState? {
        guard !blockedWindows.isEmpty else { return nil }
        return blockedWindows.removeFirst()
    }

    func saved(_ window: WindowState) {
        guard !preparingDeletion, blockedWindows.contains(where: { $0 === window }), window.deferredDocuments.isEmpty
        else { return }
        window.close()
    }

    @discardableResult func deleteProject(_ id: Project.ID, in library: ProjectLibrary) throws -> Bool {
        var affected = windows.compactMap(\.window).filter { $0.library === library && $0.projectID == id }
        for window in blockedWindows where window.library === library && window.projectID == id {
            if !affected.contains(where: { $0 === window }) { affected.append(window) }
        }
        // Saving a retained state must not release its access/ownership before the store commit.
        preparingDeletion = true
        defer { preparingDeletion = false }
        var allowed = true
        for window in affected where !window.prepareProjectDeletion() { allowed = false }
        guard allowed else { return false }
        try library.deleteProject(id)
        let fallback = library.projects.first?.id
        // No suspension between preparation, persistence, and retiring every old authorizer.
        for window in affected {
            let transitioned = window.selectProject(fallback, openLastFile: false)
            precondition(transitioned, "A prepared project deletion must retire its saved documents")
            if blockedWindows.contains(where: { $0 === window }) { window.close() }
        }
        return true
    }

    func prepareRelease(in project: Project.ID?) -> Bool {
        var allowed = true
        for window in affectedWindows(in: project) where !window.prepareForRelease() { allowed = false }
        return allowed
    }

    private func affectedWindows(in project: Project.ID?) -> [WindowState] {
        var affected = windows.compactMap(\.window).filter { $0.projectID == project }
        for window in blockedWindows where window.projectID == project {
            if !affected.contains(where: { $0 === window }) { affected.append(window) }
        }
        return affected
    }

    func rootsRemoved(in project: Project.ID?) {
        for window in affectedWindows(in: project) { window.projectRootsChanged() }
    }

    func itemTrashed(_ url: URL, in project: Project.ID?) {
        for window in allManagedWindows { window.itemTrashed(url) }
    }

    private var allManagedWindows: [WindowState] {
        var all = windows.compactMap(\.window)
        for window in blockedWindows where !all.contains(where: { $0 === window }) { all.append(window) }
        return all
    }

    func prepareDestructiveOperation(_ plan: DestructiveLifecyclePlan, in project: Project.ID?) -> Bool {
        var allowed = true
        // Retained states stay owned until persistence succeeds, including when their
        // pre-save drains a published-document queue.
        preparingDeletion = true
        defer { preparingDeletion = false }
        for window in allManagedWindows {
            let physical =
                plan.action != .unbind
                && (window.selectedFile.map { (try? DestructiveLifecyclePlan.affects(plan.item, document: $0)) ?? true }
                    ?? false)
            if window.projectID == project || physical {
                if !window.prepareForRelease() { allowed = false }
            }
        }
        return allowed
    }

    func itemMoved(from: URL, to: URL, in project: Project.ID?) {
        for window in windows.compactMap(\.window) where window.projectID == project {
            window.itemMoved(from: from, to: to)
        }
    }

    func prepareTermination() -> Bool {
        var allowed = true
        for window in windows.compactMap(\.window) where !window.prepareWindowClose() {
            allowed = false
        }
        return allowed
    }

    private func windowShowing(_ project: Project.ID) -> WindowState? {
        let showing = windows.compactMap(\.window).filter { $0.projectID == project }
        return showing.first { $0.hostWindow?.isKeyWindow == true } ?? showing.first
    }

    /// Opens a window for each project still waiting, once windows can be opened.
    private func requestWindows() {
        guard hasLaunched, let openWindow else { return }
        for _ in 0..<pending.windowsToRequest() { openWindow() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { ExternalOpens.shared.prepareTermination() ? .terminateNow : .terminateCancel }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ExternalOpens.shared.finishLaunching() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { ExternalOpens.shared.open(urls) }
    }
}

/// Hands the window that hosts a view to `onWindow`.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { WindowReaderView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowReaderView)?.onWindow = onWindow
        if let window = view.window { onWindow(window) }
    }

    private final class WindowReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
