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
        let placements = library.place(files, unsortedName: String(localized: "Unsorted"))
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
    }

    private final class WindowReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
