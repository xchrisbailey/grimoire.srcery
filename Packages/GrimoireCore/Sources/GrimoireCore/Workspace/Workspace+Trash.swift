import Darwin
import Foundation

public struct TrashRecoveryError: LocalizedError {
    public let actualTrashSucceeded: Bool
    public let originalItemVerified: Bool
    public let cause: any Error

    public var errorDescription: String? {
        let status =
            actualTrashSucceeded
            ? String(localized: "The item went to the Trash, but its configuration removal is pending.")
            : String(localized: "The trash operation needs repair. Its configuration is unchanged.")
        return status + "\n" + cause.localizedDescription
    }
}

extension Workspace {
    public var lifecycleRepairExplanation: String {
        if !pendingTrashConfigurationRemovals.isEmpty {
            return String(
                localized:
                    "A trash operation has an unknown outcome. Review its recorded configuration removal."
            )
                + "\n" + String(localized: "Retry never moves or restores files.")
        }
        return LifecycleError.pendingRepair.localizedDescription
    }

    public var pendingTrashConfigurationRemovals: [UUID] {
        (project?.pendingLifecycleOperations ?? []).filter { $0.kind == .trash }.map(\.id)
    }

    public func prepareTrash(_ item: URL) throws -> DestructiveLifecyclePlan {
        sync()
        try validateActiveTemplateOwners()
        try requireNoPendingLifecycle(at: item)
        guard let project, let reference = try templateReference(for: item), !reference.relativePath.isEmpty else {
            throw LifecycleError.unsupportedBoundary
        }
        // A separately bound root cannot be physically trashed through its ancestor.
        for root in templateRoots {
            if let location = root.url,
                try LifecyclePath.reference(rootID: root.id, root: item, url: location) != nil
            {
                throw LifecycleError.unsupportedBoundary
            }
        }
        func inside(_ reference: FileReference) throws -> Bool {
            guard let root = project.root(reference.rootID) else { return false }
            let location = url(for: FileReference(rootID: root.id, relativePath: "")) ?? root.lastKnownURL
            return try LifecyclePath.reference(rootID: root.id, root: item, url: reference.url(in: location)) != nil
        }
        let removed = try project.templateAssignments.filter { try inside($0.owner) }
        let dependencies = try project.templateAssignments.filter {
            guard !removed.contains($0), case .useSource(let source) = $0.choice else { return false }
            return try inside(source)
        }
        let scopes = try destructiveRootScopes(item: item, assignments: removed + dependencies)
        guard scopes.allSatisfy({ $0.identity != nil }) else { throw LifecycleError.pendingRepair }
        let plan = DestructiveLifecyclePlan(
            action: .trash, item: item, removedChoices: removed, brokenDependencies: dependencies,
            projectID: projectID, rootID: reference.rootID, roots: scopes,
            itemIdentity: try LifecycleIdentity(item),
            parentIdentity: try LifecycleIdentity(item.deletingLastPathComponent()))
        if !removed.isEmpty || !dependencies.isEmpty {
            let operation = try trashOperation(plan)
            var proposed = project
            proposed.pendingLifecycleOperations.append(operation)
            try operation.validate(in: project)
            try library.validatePendingLifecycleEdits(
                from: project, to: proposed, caseSensitiveNames: lifecycleOperations.caseSensitiveNames)
        }
        return plan
    }

    func trashOperation(_ plan: DestructiveLifecyclePlan) throws -> PendingLifecycleOperation {
        guard let reference = try templateReference(for: plan.item),
            let rootIdentity = plan.roots.first(where: { $0.id == reference.rootID })?.identity,
            let itemIdentity = plan.itemIdentity, let parentIdentity = plan.parentIdentity
        else { throw LifecycleError.pendingRepair }
        return PendingLifecycleOperation(
            kind: .trash, trashRoots: plan.roots,
            id: UUID(), projectID: projectID, source: reference, destination: reference,
            rootIdentity: rootIdentity, itemIdentity: itemIdentity,
            sourceParentIdentity: parentIdentity, destinationParentIdentity: parentIdentity,
            before: plan.removedChoices + plan.brokenDependencies, after: plan.brokenDependencies)
    }

    func performTrash(_ plan: DestructiveLifecyclePlan) throws -> DestructiveLifecycleResult {
        let operation =
            (!plan.removedChoices.isEmpty || !plan.brokenDependencies.isEmpty) ? try trashOperation(plan) : nil
        if let operation {
            try library.update(projectID, caseSensitiveNames: lifecycleOperations.caseSensitiveNames) {
                $0.pendingLifecycleOperations.append(operation)
            }
        }
        var actualSuccess = false
        var verified = false
        do {
            try requireTrashIdentities(plan)
            let destination = try lifecycleOperations.trash(plan.item)
            actualSuccess = true
            try requireTrashRoots(plan.roots)
            guard try LifecycleIdentity(plan.item.deletingLastPathComponent()) == plan.parentIdentity else {
                throw LifecycleError.pendingRepair
            }
            var info = stat()
            guard lstat(LifecycleIdentity.entryPath(plan.item), &info) != 0, errno == ENOENT else {
                throw LifecycleError.pendingRepair
            }
            if let destination {
                guard try LifecycleIdentity(destination) == plan.itemIdentity else {
                    throw LifecycleError.pendingRepair
                }
            }
            verified = true
            if let operation { try library.finishLifecycleOperation(operation, in: projectID, completed: true) }
            refreshAll()
            return .trashed
        } catch {
            // Only a failed live call with the original still in its unchanged scope
            // can retire preparation. Restart never infers an outcome from reappearance.
            if !actualSuccess, (try? requireTrashIdentities(plan)) != nil, let operation {
                try? library.finishLifecycleOperation(operation, in: projectID, completed: false)
            }
            refreshAll()
            throw TrashRecoveryError(actualTrashSucceeded: actualSuccess, originalItemVerified: verified, cause: error)
        }
    }

    private func requireTrashIdentities(_ plan: DestructiveLifecyclePlan) throws {
        try requireTrashRoots(plan.roots)
        guard try LifecycleIdentity(plan.item) == plan.itemIdentity,
            try LifecycleIdentity(plan.item.deletingLastPathComponent()) == plan.parentIdentity
        else { throw LifecycleError.pendingRepair }
    }

    private func requireTrashRoots(_ scopes: [DestructiveRootScope]) throws {
        for scope in scopes {
            guard let root = project?.root(scope.id), root.bookmark == scope.bookmark, root.lastKnownPath == scope.path,
                let location = url(for: FileReference(rootID: scope.id, relativePath: "")),
                try LifecycleIdentity(location) == scope.identity
            else { throw LifecycleError.pendingRepair }
        }
    }

    public func prepareTrashConfigurationRemoval(_ id: UUID) throws -> DestructiveLifecyclePlan {
        sync()
        guard let project, let operation = project.pendingLifecycleOperations.first(where: { $0.id == id }),
            operation.kind == .trash, let scopes = operation.trashRoots,
            let root = url(for: FileReference(rootID: operation.source.rootID, relativePath: ""))
        else { throw LifecycleError.pendingRepair }
        try operation.validate(in: project)
        try requireTrashRoots(scopes)
        let item = operation.source.url(in: root)
        guard try LifecycleIdentity(item.deletingLastPathComponent()) == operation.sourceParentIdentity else {
            throw LifecycleError.pendingRepair
        }
        return DestructiveLifecyclePlan(
            action: .finishTrash(id), item: item,
            removedChoices: operation.before.filter { !operation.after.contains($0) },
            brokenDependencies: operation.after, projectID: projectID, rootID: operation.source.rootID,
            roots: scopes, itemIdentity: operation.itemIdentity, parentIdentity: operation.sourceParentIdentity,
            pending: [operation])
    }
}
