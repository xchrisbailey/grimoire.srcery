import Foundation

extension ProjectLibrary {
    func validatePendingLifecycleEdits(from old: Project, to new: Project) throws {
        for operation in old.pendingLifecycleOperations {
            try validatePendingRootEdits(operation, from: old, to: new)
            guard new.pendingLifecycleOperations.contains(operation),
                new.root(operation.source.rootID) != nil,
                old.root(operation.source.rootID)?.lastKnownPath == new.root(operation.source.rootID)?.lastKnownPath
            else { throw LifecycleError.pendingRepair }
            for reference in (operation.before + operation.after).flatMap({ assignment in
                if case .useSource(let source) = assignment.choice { return [assignment.owner, source] }
                return [assignment.owner]
            }) where old.root(reference.rootID) != nil {
                guard let root = new.root(reference.rootID),
                    root.lastKnownPath == old.root(reference.rootID)?.lastKnownPath
                else { throw LifecycleError.pendingRepair }
            }
            let changed =
                old.templateAssignments.filter { !new.templateAssignments.contains($0) }
                + new.templateAssignments.filter { !old.templateAssignments.contains($0) }
            let owners = Set((operation.before + operation.after).map(\.owner))
            guard !changed.contains(where: { operation.touches($0) || owners.contains($0.owner) }) else {
                throw LifecycleError.pendingRepair
            }
        }
    }

    private func validatePendingRootEdits(_ operation: PendingLifecycleOperation, from old: Project, to new: Project)
        throws
    {
        guard
            old.roots.count != new.roots.count
                || zip(old.roots, new.roots).contains(where: {
                    $0.id != $1.id || $0.bookmark != $1.bookmark || $0.lastKnownPath != $1.lastKnownPath
                })
        else { return }
        guard let root = old.root(operation.source.rootID), let replacement = new.root(root.id) else {
            throw LifecycleError.pendingRepair
        }
        if root.bookmark != replacement.bookmark {
            let resolved = try FolderBookmark.resolve(replacement.bookmark)
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
            guard try LifecycleIdentity(resolved.url) == operation.rootIdentity else {
                throw LifecycleError.pendingRepair
            }
        }
        let rootURL = (try? FolderBookmark.resolve(root.bookmark).url) ?? root.lastKnownURL
        let paths = [operation.source.url(in: rootURL), operation.destination.url(in: rootURL)]
        func relevant(_ roots: [FolderRoot]) throws -> [UUID] {
            try roots.filter { candidate in
                let url = (try? FolderBookmark.resolve(candidate.bookmark).url) ?? candidate.lastKnownURL
                return try paths.contains { path in
                    try LifecyclePath.reference(rootID: candidate.id, root: url, url: path) != nil
                        || LifecyclePath.reference(rootID: candidate.id, root: path, url: url) != nil
                }
            }.map(\.id)
        }
        guard try relevant(old.roots) == relevant(new.roots) else { throw LifecycleError.pendingRepair }
    }

    func requireUnconfiguredRoot(_ rootID: FolderRoot.ID, in projectID: Project.ID) throws {
        guard let project = project(projectID) else { throw LibraryError.unknownProject }
        guard !project.pendingLifecycleOperations.contains(where: { $0.source.rootID == rootID }) else {
            throw LifecycleError.pendingRepair
        }
        guard
            !project.templateAssignments.contains(where: { assignment in
                if assignment.owner.rootID == rootID { return true }
                if case .useSource(let source) = assignment.choice { return source.rootID == rootID }
                return false
            })
        else { throw LifecycleError.configurationProtected }
    }

    func requireSameConfiguredRoot(_ rootID: FolderRoot.ID, in projectID: Project.ID, as url: URL) throws {
        do {
            try requireUnconfiguredRoot(rootID, in: projectID)
        } catch {
            guard let root = project(projectID)?.root(rootID),
                let resolved = try? FolderBookmark.resolve(root.bookmark)
            else { throw error }
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
            guard let old = try? LifecycleIdentity(resolved.url), let new = try? LifecycleIdentity(url), old == new
            else { throw error }
        }
    }

    func finishLifecycleOperation(_ operation: PendingLifecycleOperation, in id: Project.ID, completed: Bool) throws {
        guard let current = project(id), current.pendingLifecycleOperations.contains(operation) else {
            throw LifecycleError.invalidRecord
        }
        try operation.validate(in: current)
        var updated = current
        if completed {
            updated.templateAssignments.removeAll { operation.before.contains($0) }
            updated.templateAssignments += operation.after
            updated.lastOpenedFile = updated.lastOpenedFile.map(operation.relocated)
            updated.expandedFolders = Set(updated.expandedFolders.map(operation.relocated))
        }
        updated.pendingLifecycleOperations.removeAll { $0.id == operation.id }
        try commit(projects.map { $0.id == id ? updated : $0 })
    }
}
