import Foundation

public struct RootAccessPlan {
    public let root: FolderRoot
    public let destination: URL
    /// Includes both owned choices and choices elsewhere that reference sources in this binding.
    public let affectedAssignments: [FolderTemplateAssignment]
    public let requiresConfirmation: Bool
    let projectID: Project.ID
    let roots: [FolderRoot]
    let destinationIdentity: LifecycleIdentity
}

extension Workspace {
    /// Stores access without carrying configuration to an unconfirmed different folder.
    public func regrantAccess(to rootID: FolderRoot.ID, with url: URL) throws {
        let plan = try prepareRootAccess(to: rootID, with: url)
        guard !plan.requiresConfirmation else { throw LifecycleError.configurationProtected }
        try confirmRootAccess(plan)
    }

    /// Shows the folder under `alias` instead of its name. Empty clears it.
    public func setAlias(_ alias: String, of rootID: FolderRoot.ID) throws {
        try library.setAlias(alias, of: rootID, in: projectID)
        lastError = nil
        sync()
    }

    public func prepareRootAccess(to rootID: FolderRoot.ID, with destination: URL) throws -> RootAccessPlan {
        guard isActive else { throw TemplateAssignmentError.unavailableFolder }
        sync()
        refreshTemplateRootLocations()
        reconcileLifecycleOperations()
        refreshTemplateRootLocations()
        guard let project, let root = project.root(rootID) else { throw LibraryError.unknownRoot }
        let accessing = destination.startAccessingSecurityScopedResource()
        defer { if accessing { destination.stopAccessingSecurityScopedResource() } }
        let target = destination.resolvingSymlinksInPath()
        let identity = try LifecycleIdentity(target)
        _ = try FileManager.default.contentsOfDirectory(atPath: target.path)
        // Picking the very folder a stuck relocation recorded for this binding is how an unresolvable
        // bookmark is repaired. A different folder, or a root recorded only through references, stays refused.
        let recorded = project.pendingLifecycleOperations
            .filter { $0.kind != .trash && $0.rootIdentities[rootID] == identity }
        // Settings refuse a bookmark change that also changes the root's last-known path while a record
        // depends on it, so the exemption would only fail later at confirmation.
        if !recorded.isEmpty, !Self.isPath(target, destination, root.lastKnownPath) {
            throw LifecycleError.movedWhileRepairing(root.lastKnownPath)
        }
        let exempt = Set(recorded.map(\.id))
        try requireNoPendingLifecycle(at: target, excluding: exempt)
        if let previous = folders.first(where: { $0.id == rootID })?.url {
            try requireNoPendingLifecycle(at: previous, excluding: exempt)
        }
        guard
            !project.pendingLifecycleOperations.contains(where: { operation in
                !exempt.contains(operation.id)
                    && (operation.rootIdentities[rootID] != nil
                        || operation.recordReferences.contains { $0.rootID == rootID })
            })
        else {
            throw LifecycleError.pendingRepair
        }
        let affected = project.templateAssignments.filter { assignment in
            if assignment.owner.rootID == rootID { return true }
            if case .useSource(let source) = assignment.choice { return source.rootID == rootID }
            return false
        }
        for assignment in affected { try requireAvailableTemplateDependency(assignment, excluding: exempt) }
        let previousIdentity = previousRootIdentity(root)
        return RootAccessPlan(
            root: root, destination: destination, affectedAssignments: affected,
            requiresConfirmation: !affected.isEmpty && previousIdentity != identity && exempt.isEmpty,
            projectID: projectID, roots: project.roots, destinationIdentity: identity)
    }

    private func previousRootIdentity(_ root: FolderRoot) -> LifecycleIdentity? {
        if let pinned = templateRootIdentities[root.id] { return pinned }
        guard let resolved = try? FolderBookmark.resolve(root.bookmark) else { return nil }
        let accessing = resolved.url.startAccessingSecurityScopedResource()
        defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
        return try? LifecycleIdentity(resolved.url.resolvingSymlinksInPath())
    }

    /// Calling this method confirms carrying exactly the displayed binding's records and source references.
    public func confirmRootAccess(_ plan: RootAccessPlan) throws {
        guard plan.projectID == projectID else { throw LibraryError.unknownProject }
        let current = try prepareRootAccess(to: plan.root.id, with: plan.destination)
        guard current.roots == plan.roots, current.affectedAssignments == plan.affectedAssignments,
            current.requiresConfirmation == plan.requiresConfirmation,
            current.destinationIdentity == plan.destinationIdentity
        else { throw TemplateAssignmentError.recoveryChanged }
        try library.replaceBookmark(of: plan.root.id, in: projectID, with: plan.destination)
        lastError = nil
        // Access and watcher changes follow persistence; a failed commit leaves the old binding intact.
        sync()
    }

    private static func isPath(_ resolved: URL, _ picked: URL, _ path: String) -> Bool {
        let recorded = URL(filePath: path, directoryHint: .isDirectory)
        return picked.standardizedFileURL.path == recorded.standardizedFileURL.path
            || resolved.path == recorded.resolvingSymlinksInPath().path
    }
}
