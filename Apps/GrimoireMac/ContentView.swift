import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// One window: the project sidebar and the editor.
struct ContentView: View {
    @Environment(ProjectLibrary.self) private var library
    @State private var window: WindowState?

    var body: some View {
        Group {
            if let window {
                WindowContent(window: window)
            } else {
                Color.brand(\.page)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onAppear {
            if window == nil { window = WindowState(library: library) }
            ThemeLibrary.shared.applyAppearance()
        }
    }
}

private struct WindowContent: View {
    @Bindable var window: WindowState
    @Environment(ProjectLibrary.self) private var library
    @SceneStorage("grimoire.project") private var storedProject = ""
    @SceneStorage("grimoire.file") private var storedFile = ""
    /// The project the most recently used window showed, for windows with nothing restored.
    @AppStorage("lastProjectID") private var lastProject = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $window.columnVisibility) {
            SidebarView(window: window)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            EditorArea(window: window)
        }
        .tint(Color.brand(\.magic))
        .navigationTitle(window.document?.url.lastPathComponent ?? window.project?.name ?? "Grimoire")
        .navigationSubtitle(window.document == nil ? "" : window.project?.name ?? "")
        .toolbar {
            if let document = window.document {
                ToolbarItem(placement: .status) { InkDot(isWet: document.isDirty) }
                ToolbarItem(placement: .primaryAction) { ModePicker(mode: $window.editorMode) }
            }
        }
        .toolbar(window.focusMode ? .hidden : .automatic, for: .windowToolbar)
        .background(FocusChrome(isFocused: window.focusMode))
        .background(DocumentEditedMarker(isEdited: window.document?.isDirty ?? false))
        .focusedSceneValue(\.windowState, window)
        .onKeyPress(.escape) {
            guard window.focusMode else { return .ignored }
            window.setFocusMode(false)
            return .handled
        }
        .onChange(of: window.columnVisibility) {
            // Opening the sidebar (its title bar button or ⌃⌘S) wakes from focus mode.
            if window.focusMode, window.columnVisibility != .detailOnly { window.setFocusMode(false) }
        }
        .onAppear {
            if library.projects.isEmpty { library.createProject(named: String(localized: "Grimoire")) }
            window.restore(projectID: storedProject, file: storedFile, fallbackProject: lastProject)
        }
        .onDisappear { window.close() }
        .onChange(of: window.projectID) {
            storedProject = window.projectID?.uuidString ?? ""
            if !storedProject.isEmpty { lastProject = storedProject }
        }
        .onChange(of: window.selectedFile) { storedFile = window.restorationFile }
        .onChange(of: window.project?.roots) { window.projectRootsChanged() }
        .onChange(of: Preferences.shared.fileExtensions(for: window.project)) { window.preferencesChanged() }
        .onChange(of: Preferences.shared.autosaveDelay) { window.preferencesChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            window.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            window.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            window.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            window.document?.checkDisk()
        }
    }
}
