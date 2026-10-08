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
                    .background(WindowReader { window.hostWindow = $0 })
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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) { ShareMenu(window: window, document: document) }
                ToolbarItem(placement: .primaryAction) { ModePicker(mode: $window.editorMode) }
            }
        }
        .overlay(alignment: .top) { paletteOverlay }
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
            let stored = (project: storedProject, file: storedFile, fallback: lastProject)
            ExternalOpens.shared.whenLaunched {
                if library.projects.isEmpty { library.createProject(named: String(localized: "Grimoire")) }
                window.restore(projectID: stored.project, file: stored.file, fallbackProject: stored.fallback)
            }
        }
        .onDisappear { window.close() }
        .onChange(of: window.projectID) {
            storedProject = window.projectID?.uuidString ?? ""
            if !storedProject.isEmpty { lastProject = storedProject }
        }
        .onChange(of: window.selectedFile) { storedFile = window.restorationFile }
        .modifier(FollowsProject(window: window))
        .modifier(SavesWithApp(window: window))
    }

    // MARK: - Palettes

    @ViewBuilder private var paletteOverlay: some View {
        if let palette = window.palette {
            ZStack(alignment: .top) {
                Color.black.opacity(0.001)
                    .onTapGesture { window.palette = nil }
                PaletteView(palette: palette, items: items(for: palette)) {
                    window.palette = nil
                    DispatchQueue.main.async { window.editor.focusEditor() }
                }
                .padding(.top, 60)
                .id(palette)
            }
        }
    }

    private func items(for palette: Palette) -> [PaletteItem] {
        switch palette {
        case .summon:
            window.index.documents.map { document in
                PaletteItem(
                    id: document.url.absoluteString, title: document.name, subtitle: document.path, icon: "doc.text",
                    keywords: document.path
                ) { window.select(document.url) }
            }
        case .headings:
            window.editor.headings.map { heading in
                PaletteItem(
                    id: String(heading.offset), title: heading.title,
                    shortcut: String(repeating: "#", count: heading.level),
                    indent: heading.level - 1
                ) { window.editor.reveal(NSRange(location: heading.offset, length: 0)) }
            }
        case .incantations:
            Incantations.items(
                for: window, openWindow: { openWindow(id: "project") }, openSettings: { openSettings() })
        }
    }
}

/// Keeps the workspace and the editor current as the project and the preferences change.
private struct FollowsProject: ViewModifier {
    let window: WindowState

    func body(content: Content) -> some View {
        content
            .onChange(of: window.project?.roots) { window.projectRootsChanged() }
            .onChange(of: window.project?.looseFiles) { window.projectRootsChanged() }
            .onChange(of: window.workspace?.scanCount) { window.workspaceScanned() }
            .onChange(of: Preferences.shared.fileExtensions(for: window.project)) { window.preferencesChanged() }
            .onChange(of: Preferences.shared.autosaveDelay) { window.preferencesChanged() }
            .onChange(of: Preferences.shared.fileListing) { window.preferencesChanged() }
    }
}

/// Saves the open file as the app or window loses focus or quits, and rechecks the disk
/// when the app comes back.
private struct SavesWithApp: ViewModifier {
    let window: WindowState

    func body(content: Content) -> some View {
        content
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
                window.refreshLooseFiles()
                window.document?.checkDisk()
            }
    }
}
