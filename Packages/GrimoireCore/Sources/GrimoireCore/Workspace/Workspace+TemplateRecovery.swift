import Foundation

/// A settings-only edit. Preparing or discarding it never changes files or assignments.
public struct TemplateRecoveryPlan {
    public let assignment: FolderTemplateAssignment
    public let destination: URL?
    public let destinationOwner: FileReference?
    let projectID: Project.ID
    let roots: [FolderRoot]
    let choices: [FolderTemplateAssignment]
    let destinationIdentity: LifecycleIdentity?
    let rootIdentity: LifecycleIdentity?
}

extension Workspace {
    /// A nil destination prepares Remove Assignment; a picker cancellation must not call confirm.
    public func prepareTemplateRecovery(_ assignment: FolderTemplateAssignment, locating destination: URL?) throws
        -> TemplateRecoveryPlan
    {
        sync()
        refreshTemplateRootLocations()
        reconcileLifecycleOperations()
        refreshTemplateRootLocations()
        try requireAvailableTemplateDependency(assignment)
        guard isActive, let project, assignment.state == .unresolved,
            project.templateAssignments.contains(assignment), project.root(assignment.owner.rootID) != nil
        else { throw TemplateAssignmentError.unavailableFolder }
        let owner = try destination.map { try templateOwner(for: $0) }
        if let owner, let destination {
            try requireNoPendingLifecycle(at: destination)
            try requireVacantTemplateOwner(owner, replacing: assignment)
        }
        return TemplateRecoveryPlan(
            assignment: assignment, destination: destination, destinationOwner: owner,
            projectID: projectID, roots: project.roots, choices: project.templateAssignments,
            destinationIdentity: try destination.map { try LifecycleIdentity($0.resolvingSymlinksInPath()) },
            rootIdentity: try owner.map { try recoveryRootIdentity($0.rootID) })
    }

    public func confirmTemplateRecovery(_ plan: TemplateRecoveryPlan) throws {
        guard plan.projectID == projectID else { throw TemplateAssignmentError.invalidReference }
        let current = try prepareTemplateRecovery(plan.assignment, locating: plan.destination)
        guard current.roots == plan.roots, current.destinationOwner == plan.destinationOwner,
            current.choices == plan.choices,
            current.destinationIdentity == plan.destinationIdentity, current.rootIdentity == plan.rootIdentity
        else { throw TemplateAssignmentError.recoveryChanged }
        try library.update(projectID, caseSensitiveNames: lifecycleOperations.caseSensitiveNames) { project in
            project.templateAssignments.removeAll { $0 == plan.assignment }
            if let owner = plan.destinationOwner {
                var located = plan.assignment
                located.owner = owner
                located.state = .active
                project.templateAssignments.append(located)
            }
        }
    }

    private func recoveryRootIdentity(_ id: FolderRoot.ID) throws -> LifecycleIdentity {
        guard let root = templateRoots.first(where: { $0.id == id })?.url else {
            throw TemplateAssignmentError.unavailableFolder
        }
        let identity = try LifecycleIdentity(root.resolvingSymlinksInPath())
        guard identity == templateRootIdentities[id] else { throw TemplateAssignmentError.unavailableFolder }
        return identity
    }

    private func requireVacantTemplateOwner(_ owner: FileReference, replacing old: FolderTemplateAssignment) throws {
        guard let target = url(for: owner) else { throw TemplateAssignmentError.unavailableFolder }
        let targetParts = try LifecyclePath.components(target)
        for assignment in project?.templateAssignments ?? [] where assignment != old {
            // Separately bound roots retain masked outer choices; only this owning binding is being edited.
            guard assignment.owner.rootID == owner.rootID else { continue }
            guard let existing = url(for: assignment.owner) else { continue }
            let parts = try LifecyclePath.components(existing)
            guard parts.count == targetParts.count else { continue }
            if try LifecyclePath.overlaps(target, existing, caseSensitiveNames: lifecycleOperations.caseSensitiveNames)
            {
                throw TemplateAssignmentError.conflictingChoices
            }
        }
    }
}
