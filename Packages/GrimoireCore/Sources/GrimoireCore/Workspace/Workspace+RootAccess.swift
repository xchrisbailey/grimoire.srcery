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
        try requireNoPendingLifecycle(at: target)
        if let previous = folders.first(where: { $0.id == rootID })?.url {
            try requireNoPendingLifecycle(at: previous)
        }
        guard
            !project.pendingLifecycleOperations.contains(where: { operation in
                operation.rootIdentities[rootID] != nil || operation.recordReferences.contains { $0.rootID == rootID }
            })
        else {
            throw LifecycleError.pendingRepair
        }
        let affected = project.templateAssignments.filter { assignment in
            if assignment.owner.rootID == rootID { return true }
            if case .useSource(let source) = assignment.choice { return source.rootID == rootID }
            return false
        }
        for assignment in affected { try requireAvailableTemplateDependency(assignment) }
        let previousIdentity = previousRootIdentity(root)
        return RootAccessPlan(
            root: root, destination: destination, affectedAssignments: affected,
            requiresConfirmation: !affected.isEmpty && previousIdentity != identity,
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
}
