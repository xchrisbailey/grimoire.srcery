import GrimoireCore
import SwiftUI

/// Runs the tree's file operations and holds the prompts they need (rename, alias,
/// banish, errors).
@MainActor @Observable
final class FileActions {
    var renaming: URL?
    var newName = ""
    /// The bound folder being given an alias, and the name it had when the prompt opened.
    var aliasing: (id: FolderRoot.ID, name: String)?
    var newAlias = ""
    var destructivePlan: DestructiveLifecyclePlan?
    var destructiveNotice: String?
    var error: Error?
    var configuringTemplate: URL?
    var creationPlan: DocumentCreationPlan?
    var creationStem = ""
    var creationNameEdited = false
    var creationNotice: String?
    var creationSourceFailed = false
    var creationAttemptFailed = false
    private var pendingHandoff: PublishedDocument?
    private var pendingTemplateEdit: URL?
    /// Folders still to be offered an alias after this one, from binding several at once.
    private var aliasQueue: [(id: FolderRoot.ID, name: String)] = []

    /// Called after a page is conjured, so the window can open it.
    @ObservationIgnored var didCreate: ((PublishedDocument) -> Void)?
    /// Called after an item is renamed or moved, with its old and new URLs.
    @ObservationIgnored var didMove: ((URL, URL) -> Void)?
    /// Called after an item goes to the Trash.
    @ObservationIgnored var didTrash: ((URL) -> Void)?
    /// Called before a folder or loose file leaves the project and its access ends, so the
    /// window can save what it has open while it still can.
    @ObservationIgnored var willRelease: (() -> Bool)?
    @ObservationIgnored var willPerformDestructiveOperation: ((DestructiveLifecyclePlan) -> Bool)?
    @ObservationIgnored var didUnbind: (() -> Void)?
    @ObservationIgnored var retryReconciliation: (() -> Void)?
    /// Conjures a page in `folder` and opens it, then offers to name it when `rename` is set.
    @discardableResult
    func createDocument(in folder: URL, workspace: Workspace, rename: Bool = true) -> URL? {
        do {
            let plan = try workspace.prepareDocument(in: folder, filenamePattern: Preferences.shared.newFileName)
            if plan.requiresNaming {
                creationPlan = plan
                creationStem = plan.suggestedStem
                creationNameEdited = false
                creationNotice = nil
                creationSourceFailed = false
                creationAttemptFailed = false
                return nil
            }
            return handleCreation(
                workspace.createDocument(plan, naming: .generated), workspace: workspace, rename: rename)
        } catch {
            self.error = error
            return nil
        }
    }

    func confirmCreation(workspace: Workspace, recovery: DocumentRecoveryIntent = .retry) {
        guard let plan = creationPlan else { return }
        let naming: DocumentNamingIntent = creationNameEdited ? .edited(creationStem) : .generated
        creationSourceFailed = false
        creationAttemptFailed = false
        _ = handleCreation(
            workspace.createDocument(plan, naming: naming, recovery: recovery), workspace: workspace, rename: false)
    }

    func cancelCreation(workspace: Workspace) {
        if let plan = creationPlan {
            _ = workspace.createDocument(plan, naming: .generated, confirmed: false)
        }
        creationPlan = nil
    }

    func replaceCreationSource(_ source: URL, workspace: Workspace) {
        guard let plan = creationPlan else { return }
        switch workspace.repairDocumentTemplate(plan, replacement: source) {
        case .repaired(let updated):
            creationPlan = updated
            creationSourceFailed = false
            creationAttemptFailed = false
            creationNotice = String(
                localized:
                    "The replacement was saved. You can create the document or cancel without undoing the repair.")
        case .reviewNeeded(let updated):
            _ = handleCreation(.reviewNeeded(updated), workspace: workspace, rename: false)
        case .failed(let failure):
            creationNotice = failure.localizedDescription
        case .savedButUnavailable(let failure):
            creationSourceFailed = false
            creationAttemptFailed = true
            creationNotice =
                String(localized: "The replacement was saved, but creation details are unavailable.")
                + "\n" + failure.localizedDescription
        case .cancelled:
            break
        }
    }

    func creationDismissed() {
        creationPlan = nil
        guard let published = pendingHandoff else { return }
        pendingHandoff = nil
        didCreate?(published)
    }

    func openTemplateAfterDismissal(_ source: PublishedDocument, workspace: Workspace) {
        workspace.refresh(of: source.url)
        workspace.setExpanded(source.url.deletingLastPathComponent(), true)
        pendingHandoff = source
    }

    func editTemplateAfterDismissal(_ source: URL) {
        pendingTemplateEdit = source
    }

    func templateConfigurationDismissed(select: (URL) -> Void) {
        configuringTemplate = nil
        if let source = pendingTemplateEdit {
            pendingTemplateEdit = nil
            select(source)
        }
        creationDismissed()
    }

    private func handleCreation(_ result: DocumentCreationResult, workspace: Workspace, rename: Bool) -> URL? {
        switch result {
        case .published(let published):
            return finishCreation(published, workspace: workspace, rename: rename)
        case .reviewNeeded(let updated):
            creationSourceFailed = false
            creationAttemptFailed = false
            if creationPlan == nil {
                creationStem = updated.suggestedStem
                creationNameEdited = false
            }
            creationPlan = updated
            creationNotice = String(localized: "Creation details changed. Review them, then confirm again.")
        case .invalidName(let failure):
            creationNotice = failure.localizedDescription
        case .sourceFailure(let plan, let failure):
            showSourceFailure(plan, failure: failure, workspace: workspace)
        case .failed(let failure), .contextUnavailable(let failure):
            creationAttemptFailed = true
            creationNotice = failure.localizedDescription
            if creationPlan == nil { error = failure }
        case .publishedButUnavailable(let url):
            creationPlan = nil
            creationNotice = nil
            error = CreatedDocumentOpenError(url: url)
        case .alreadyPublished:
            creationPlan = nil
            creationNotice = nil
        case .cancelled:
            break
        }
        return nil
    }

    private func creationSourcePath(_ plan: DocumentCreationPlan) -> String {
        if let url = plan.source { return url.path }
        if case .useSource(let reference) = plan.assignment?.choice {
            return "[" + reference.rootID.uuidString + "]/" + reference.relativePath
        }
        return ""
    }

    private func finishCreation(_ published: PublishedDocument, workspace: Workspace, rename: Bool) -> URL {
        workspace.refresh(of: published.url)
        workspace.setExpanded(published.url.deletingLastPathComponent(), true)
        // Destination review can present a sheet even when the output keeps legacy editor behavior.
        let awaitsDismissal = creationPlan != nil
        creationPlan = nil
        creationNotice = nil
        if awaitsDismissal {
            pendingHandoff = published
        } else {
            didCreate?(published)
            if rename { startRename(published.url) }
        }
        return published.url
    }

}
extension FileActions {
    private func showSourceFailure(_ plan: DocumentCreationPlan, failure: Error, workspace: Workspace) {
        creationPlan = plan
        if !creationNameEdited { creationStem = plan.suggestedStem }
        creationSourceFailed = true
        creationNotice =
            String(localized: "Template source: \(creationSourcePath(plan))")
            + "\n"
            + String(
                localized: "Owning folder: \(plan.assignment.flatMap { workspace.url(for: $0.owner) }?.path ?? "")")
            + "\n" + failure.localizedDescription
    }

    func createFolder(in folder: URL, workspace: Workspace) {
        perform(workspace, near: folder) {
            let url = try FileOperations.createFolder(in: folder)
            workspace.setExpanded(folder, true)
            startRename(url)
        }
    }

    func startRename(_ url: URL) {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        newName = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        renaming = url
    }

    func finishRename(workspace: Workspace) {
        guard let url = renaming else { return }
        renaming = nil
        perform(workspace, near: url) {
            let result = workspace.rename(url, to: newName)
            if let renamed = result.movedURL, renamed != url { didMove?(url, renamed) }
            if let error = result.error { throw error }
        }
    }

    func banish(_ url: URL, workspace: Workspace) {
        do {
            destructivePlan = try workspace.prepareTrash(url)
            destructiveNotice = nil
        } catch { self.error = error }
    }

    func finishTrashConfiguration(_ id: UUID, workspace: Workspace) {
        do {
            destructivePlan = try workspace.prepareTrashConfigurationRemoval(id)
            destructiveNotice = nil
        } catch { self.error = error }
    }

    /// Moves dropped items into `folder`. Only items inside this workspace are accepted.
    func move(_ urls: [URL], into folder: URL, workspace: Workspace) -> Bool {
        let inside = urls.filter { workspace.reference(for: $0) != nil }
        guard !inside.isEmpty else { return false }
        for url in inside {
            perform(workspace, near: url) {
                let result = workspace.move(url, into: folder)
                if let moved = result.movedURL, moved != url { didMove?(url, moved) }
                if let legacy = result.legacyMovedURL, legacy != url { didMove?(url, legacy) }
                if let error = result.error { throw error }
            }
        }
        workspace.refresh(of: folder)
        return true
    }

    /// Asks for an alias for each folder in turn, prefilled with what it's called now.
    func offerAliases(for roots: [FolderRoot]) {
        aliasQueue += roots.map { ($0.id, $0.name) }
        if aliasing == nil { showNextAlias() }
    }

    func startAlias(_ root: FolderRoot) {
        aliasQueue.removeAll()
        aliasing = (root.id, root.name)
        newAlias = root.displayName
    }

    func finishAlias(workspace: Workspace) {
        guard let aliasing else { return }
        do {
            try workspace.setAlias(newAlias, of: aliasing.id)
        } catch {
            self.error = error
        }
    }

    /// The alias prompt closed: shows the next queued folder once it's gone.
    func aliasDismissed() {
        aliasing = nil
        guard !aliasQueue.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            showNextAlias()
        }
    }

    private func showNextAlias() {
        guard aliasing == nil, !aliasQueue.isEmpty else { return }
        let next = aliasQueue.removeFirst()
        aliasing = next
        newAlias = next.name
    }

    func removeLooseFile(_ file: BoundFile, from workspace: Workspace) {
        guard willRelease?() ?? true else { return }
        do {
            try workspace.removeLooseFile(file.id)
        } catch {
            self.error = error
        }
    }

    private func perform(_ workspace: Workspace, near url: URL, _ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            self.error = error
        }
        workspace.refresh(of: url)
    }
}
extension Workspace {
    /// Rescans the root holding `url`.
    func refresh(of url: URL) {
        if let reference = reference(for: url) { refresh(reference.rootID) }
    }
}
extension View {
    /// The rename and alias prompts, banish confirmation and error alert for a window's file actions.
    func fileActionPrompts(_ actions: FileActions, workspace: Workspace?, select: @escaping (URL) -> Void) -> some View
    {
        modifier(FileActionPrompts(actions: actions, workspace: workspace, select: select))
    }
}

private struct FileActionPrompts: ViewModifier {
    @Bindable var actions: FileActions
    let workspace: Workspace?
    let select: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .modifier(DocumentCreationPrompt(actions: actions, workspace: workspace))
            .modifier(TemplateConfigurationPrompt(actions: actions, workspace: workspace, select: select))
            .modifier(DestructiveLifecyclePrompt(actions: actions, workspace: workspace))
            .alert(
                String(localized: "Rename “\(actions.renaming?.lastPathComponent ?? "")”"),
                isPresented: Binding(get: { actions.renaming != nil }, set: { if !$0 { actions.renaming = nil } })
            ) {
                TextField("Name", text: $actions.newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let workspace else { return }
                    actions.finishRename(workspace: workspace)
                }
            }
            .alert(
                String(localized: "Alias for “\(actions.aliasing?.name ?? "")”"),
                isPresented: Binding(get: { actions.aliasing != nil }, set: { if !$0 { actions.aliasDismissed() } })
            ) {
                TextField("Alias", text: $actions.newAlias)
                Button("Skip", role: .cancel) {}
                Button("Save") {
                    guard let workspace else { return }
                    actions.finishAlias(workspace: workspace)
                }
            } message: {
                Text("The sidebar shows this name instead of the folder's. Leave it empty to use the folder's name.")
            }
            .alert(
                actions.error?.localizedDescription ?? "",
                isPresented: Binding(get: { actions.error != nil }, set: { if !$0 { actions.error = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
    }

}

private struct TemplateConfigurationPrompt: ViewModifier {
    @Bindable var actions: FileActions
    let workspace: Workspace?
    let select: (URL) -> Void

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { actions.configuringTemplate != nil },
                set: { if !$0 { actions.configuringTemplate = nil } }),
            onDismiss: { actions.templateConfigurationDismissed(select: select) },
            content: { templateSheet })
    }

    @ViewBuilder private var templateSheet: some View {
        if let workspace, let folder = actions.configuringTemplate {
            ContentTemplateSheet(folder: folder, workspace: workspace, actions: actions)
        }
    }
}
