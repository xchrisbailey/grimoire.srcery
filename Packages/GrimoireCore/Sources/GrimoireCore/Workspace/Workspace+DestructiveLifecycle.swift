import Foundation

public struct DestructiveLifecyclePlan: Hashable, Sendable {
    public enum Action: Hashable, Sendable { case unbind, trash, finishTrash(UUID) }
    public let action: Action
    public let item: URL
    public let removedChoices: [FolderTemplateAssignment]
    public let brokenDependencies: [FolderTemplateAssignment]
    let projectID: UUID
    let rootID: UUID
    let roots: [DestructiveRootScope]
    var itemIdentity: LifecycleIdentity?
    var parentIdentity: LifecycleIdentity?
    var pending: [PendingLifecycleOperation] = []

    public static func affects(_ item: URL, document: URL) throws -> Bool {
        try LifecyclePath.overlaps(item, document, caseSensitiveNames: LifecyclePath.volumeCaseSensitiveNames)
    }
}

struct DestructiveRootScope: Codable, Hashable, Sendable {
    let id: UUID
    let bookmark: Data
    let path: String
    let resolvedPath: String
    let identity: LifecycleIdentity?
}

public enum DestructiveLifecycleResult: Equatable {
    case completed, cancelled, trashed
    case reviewNeeded(DestructiveLifecyclePlan)
}

extension Workspace {
    public func prepareUnbind(_ rootID: FolderRoot.ID) throws -> DestructiveLifecyclePlan {
        sync()
        guard let project, let root = project.root(rootID) else { throw LibraryError.unknownRoot }
        let removed = project.templateAssignments.filter { $0.owner.rootID == rootID }
        let dependencies = project.templateAssignments.filter {
            guard $0.owner.rootID != rootID, case .useSource(let source) = $0.choice else { return false }
            return source.rootID == rootID
        }
        let item = url(for: FileReference(rootID: rootID, relativePath: "")) ?? root.lastKnownURL
        try requireNoPendingLifecycle(at: item)
        // The normal staged-edit validator also reserves affected owner/source records,
        // including dependencies owned outside the spatial subtree.
        var proposed = project
        proposed.roots.removeAll { $0.id == rootID }
        proposed.templateAssignments.removeAll { $0.owner.rootID == rootID }
        try library.validatePendingLifecycleEdits(
            from: project, to: proposed, caseSensitiveNames: lifecycleOperations.caseSensitiveNames)
        return DestructiveLifecyclePlan(
            action: .unbind, item: item, removedChoices: removed, brokenDependencies: dependencies,
            projectID: projectID, rootID: rootID,
            roots: try destructiveRootScopes(item: item, assignments: removed + dependencies))
    }

    @discardableResult
    public func confirmDestructiveOperation(_ plan: DestructiveLifecyclePlan, confirmed: Bool = true) throws
        -> DestructiveLifecycleResult
    {
        guard confirmed else { return .cancelled }
        guard plan.projectID == projectID else { throw LibraryError.unknownProject }
        let current: DestructiveLifecyclePlan
        switch plan.action {
        case .unbind: current = try prepareUnbind(plan.rootID)
        case .trash: current = try prepareTrash(plan.item)
        case .finishTrash(let id): current = try prepareTrashConfigurationRemoval(id)
        }
        guard current == plan else { return .reviewNeeded(current) }
        switch plan.action {
        case .trash: return try performTrash(plan)
        case .finishTrash(let id):
            guard let operation = project?.pendingLifecycleOperations.first(where: { $0.id == id }) else {
                throw LifecycleError.invalidRecord
            }
            try library.finishLifecycleOperation(operation, in: projectID, completed: true)
            return .completed
        case .unbind: break
        }
        try library.commitUnbind(plan.rootID, from: projectID)
        lastError = nil
        sync()
        return .completed
    }

    func destructiveRootScopes(item: URL, assignments: [FolderTemplateAssignment]) throws -> [DestructiveRootScope] {
        let ids = Set(
            assignments.flatMap { assignment in
                if case .useSource(let source) = assignment.choice { return [assignment.owner.rootID, source.rootID] }
                return [assignment.owner.rootID]
            })
        return try (project?.roots ?? []).compactMap { root in
            let live = url(for: FileReference(rootID: root.id, relativePath: ""))
            let location = live ?? root.lastKnownURL
            guard
                try ids.contains(root.id)
                    || LifecyclePath.overlaps(
                        item, location, caseSensitiveNames: lifecycleOperations.caseSensitiveNames)
            else { return nil }
            return DestructiveRootScope(
                id: root.id, bookmark: root.bookmark, path: root.lastKnownPath,
                resolvedPath: location.standardizedFileURL.resolvingSymlinksInPath().path,
                identity: live.flatMap { try? LifecycleIdentity($0) })
        }
    }
}

extension ProjectLibrary {
    func commitUnbind(_ rootID: FolderRoot.ID, from projectID: Project.ID) throws {
        guard project(projectID)?.root(rootID) != nil else { throw LibraryError.unknownRoot }
        try update(projectID) { project in
            project.roots.removeAll { $0.id == rootID }
            project.templateAssignments.removeAll { $0.owner.rootID == rootID }
            project.expandedFolders = project.expandedFolders.filter { $0.rootID != rootID }
            if project.lastOpenedFile?.rootID == rootID { project.lastOpenedFile = nil }
        }
    }
}
