import Foundation

extension ProjectLibrary {
    func validatePendingLifecycleEdits(from old: Project, to new: Project, caseSensitiveNames: (URL) -> Bool?) throws {
        if old.pendingLifecycleOperations != new.pendingLifecycleOperations {
            try validatePendingPathReservations(new, caseSensitiveNames: caseSensitiveNames)
        }
        for operation in old.pendingLifecycleOperations {
            guard
                !new.pendingLifecycleOperations.contains(where: {
                    $0.id != operation.id && operation.conflicts(with: $0)
                })
            else { throw LifecycleError.pendingRepair }
            try validatePendingRootEdits(operation, from: old, to: new, caseSensitiveNames: caseSensitiveNames)
            guard new.pendingLifecycleOperations.contains(operation),
                operation.rootIdentities.keys.allSatisfy({ id in
                    new.root(id) != nil && old.root(id)?.lastKnownPath == new.root(id)?.lastKnownPath
                })
            else { throw LifecycleError.pendingRepair }
            for reference in (operation.before + operation.after).flatMap({ assignment in
                if case .useSource(let source) = assignment.choice { return [assignment.owner, source] }
                return [assignment.owner]
            }) where old.root(reference.rootID) != nil {
                guard let root = new.root(reference.rootID),
                    root.lastKnownPath == old.root(reference.rootID)?.lastKnownPath
                else { throw LifecycleError.pendingRepair }
                if let previous = old.root(reference.rootID), previous.bookmark != root.bookmark {
                    try requireSameRootIdentity(previous, replacement: root)
                }
            }
            let changed =
                old.templateAssignments.filter { !new.templateAssignments.contains($0) }
                + new.templateAssignments.filter { !old.templateAssignments.contains($0) }
            let owners = Set((operation.before + operation.after).map(\.owner))
            guard
                try !changed.contains(where: {
                    try operation.touches($0) || owners.contains($0.owner)
                        || touchesPendingPaths(
                            $0, operation: operation, in: old, caseSensitiveNames: caseSensitiveNames)
                        || touchesPendingPaths(
                            $0, operation: operation, in: new, caseSensitiveNames: caseSensitiveNames)
                })
            else {
                throw LifecycleError.pendingRepair
            }
        }
    }

    private func validatePendingPathReservations(_ project: Project, caseSensitiveNames: (URL) -> Bool?) throws {
        for (index, operation) in project.pendingLifecycleOperations.enumerated() {
            let roots = try reservationRoots(operation, in: project)
            for other in project.pendingLifecycleOperations.dropFirst(index + 1) {
                guard !operation.conflicts(with: other) else { throw LifecycleError.pendingRepair }
                let otherRoots = try reservationRoots(other, in: project)
                try requireNoEndpointRecordConflict(
                    operation, roots: roots, with: other, in: project, caseSensitiveNames: caseSensitiveNames)
                try requireNoEndpointRecordConflict(
                    other, roots: otherRoots, with: operation, in: project, caseSensitiveNames: caseSensitiveNames)
                if try LifecyclePath.reserves(
                    other.source.url(in: reservationRoot(other.source.rootID, in: project)),
                    operation: operation, roots: roots,
                    caseSensitiveNames: caseSensitiveNames)
                {
                    throw LifecycleError.pendingRepair
                }
                for left in operation.reservedReferences {
                    for right in other.reservedReferences {
                        guard let root = roots[left.rootID], let otherRoot = otherRoots[right.rootID] else {
                            throw LifecycleError.pendingRepair
                        }
                        if try LifecyclePath.overlaps(
                            left, in: root, right, in: otherRoot, caseSensitiveNames: caseSensitiveNames)
                        {
                            throw LifecycleError.pendingRepair
                        }
                    }
                }
            }
        }
    }

    private func reservationRoot(_ id: FolderRoot.ID, in project: Project) throws -> URL {
        guard let root = project.root(id) else { throw LifecycleError.invalidRecord }
        return (try? FolderBookmark.resolve(root.bookmark).url) ?? root.lastKnownURL
    }

    private func requireNoEndpointRecordConflict(
        _ operation: PendingLifecycleOperation, roots: [UUID: URL], with other: PendingLifecycleOperation,
        in project: Project, caseSensitiveNames: (URL) -> Bool?
    ) throws {
        for endpoint in operation.reservedReferences {
            guard let root = roots[endpoint.rootID] else { throw LifecycleError.pendingRepair }
            for reference in other.recordReferences where project.root(reference.rootID) != nil {
                if try LifecyclePath.contains(
                    endpoint, in: root, reference, in: reservationRoot(reference.rootID, in: project),
                    caseSensitiveNames: caseSensitiveNames)
                {
                    throw LifecycleError.pendingRepair
                }
            }
        }
    }

    private func reservationRoots(_ operation: PendingLifecycleOperation, in project: Project) throws -> [UUID: URL] {
        try Dictionary(
            uniqueKeysWithValues: operation.rootIdentities.keys.map { ($0, try reservationRoot($0, in: project)) })
    }

    private func touchesPendingPaths(
        _ assignment: FolderTemplateAssignment, operation: PendingLifecycleOperation,
        in project: Project, caseSensitiveNames: (URL) -> Bool?
    ) throws -> Bool {
        // Last-known paths are conservative mutation guards only, never evidence for completing intent.
        let roots = try reservationRoots(operation, in: project)
        var references = [assignment.owner]
        if case .useSource(let source) = assignment.choice { references.append(source) }
        return try references.contains { reference in
            guard let bound = project.root(reference.rootID) else { return false }
            let boundURL = (try? FolderBookmark.resolve(bound.bookmark).url) ?? bound.lastKnownURL
            if try LifecyclePath.reserves(
                reference.url(in: boundURL), operation: operation, roots: roots,
                caseSensitiveNames: caseSensitiveNames)
            {
                return true
            }
            return try operation.reservedReferences.contains { reserved in
                guard let rootURL = roots[reserved.rootID] else { throw LifecycleError.pendingRepair }
                return try LifecyclePath.overlaps(
                    reference, in: boundURL, reserved, in: rootURL,
                    caseSensitiveNames: caseSensitiveNames)
                    || LifecyclePath.overlaps(
                        reference.url(in: boundURL), reference: reserved, in: rootURL,
                        caseSensitiveNames: caseSensitiveNames)
            }
        }
    }

    private func requireSameRootIdentity(_ previous: FolderRoot, replacement: FolderRoot) throws {
        let old = try FolderBookmark.resolve(previous.bookmark).url
        let new = try FolderBookmark.resolve(replacement.bookmark).url
        let accessingOld = old.startAccessingSecurityScopedResource()
        let accessingNew = new.startAccessingSecurityScopedResource()
        defer {
            if accessingNew { new.stopAccessingSecurityScopedResource() }
            if accessingOld { old.stopAccessingSecurityScopedResource() }
        }
        guard try LifecycleIdentity(old) == LifecycleIdentity(new) else { throw LifecycleError.pendingRepair }
    }

    private func validatePendingRootEdits(
        _ operation: PendingLifecycleOperation, from old: Project, to new: Project,
        caseSensitiveNames: (URL) -> Bool?
    )
        throws
    {
        guard
            old.roots.count != new.roots.count
                || zip(old.roots, new.roots).contains(where: {
                    $0.id != $1.id || $0.bookmark != $1.bookmark || $0.lastKnownPath != $1.lastKnownPath
                })
        else { return }
        for (id, identity) in operation.rootIdentities {
            guard let root = old.root(id), let replacement = new.root(id) else {
                throw LifecycleError.pendingRepair
            }
            if root.bookmark != replacement.bookmark {
                let resolved = try FolderBookmark.resolve(replacement.bookmark)
                let accessing = resolved.url.startAccessingSecurityScopedResource()
                defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
                guard try LifecycleIdentity(resolved.url) == identity else {
                    throw LifecycleError.pendingRepair
                }
            }
        }
        let reservedRoots = try reservationRoots(operation, in: old)
        func relevant(_ roots: [FolderRoot]) throws -> [UUID] {
            try roots.filter { candidate in
                let url = (try? FolderBookmark.resolve(candidate.bookmark).url) ?? candidate.lastKnownURL
                return try LifecyclePath.reserves(
                    url, operation: operation, roots: reservedRoots,
                    caseSensitiveNames: caseSensitiveNames)
            }.map(\.id)
        }
        guard try relevant(old.roots) == relevant(new.roots) else { throw LifecycleError.pendingRepair }
    }

    func requireUnconfiguredRoot(_ rootID: FolderRoot.ID, in projectID: Project.ID) throws {
        guard let project = project(projectID) else { throw LibraryError.unknownProject }
        guard !project.pendingLifecycleOperations.contains(where: { $0.rootIdentities[rootID] != nil }) else {
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
            if operation.kind == .relocation {
                updated.lastOpenedFile = updated.lastOpenedFile.map(operation.relocated)
                updated.expandedFolders = Set(updated.expandedFolders.map(operation.relocated))
            }
        }
        updated.pendingLifecycleOperations.removeAll { $0.id == operation.id }
        try commit(projects.map { $0.id == id ? updated : $0 })
    }
}
