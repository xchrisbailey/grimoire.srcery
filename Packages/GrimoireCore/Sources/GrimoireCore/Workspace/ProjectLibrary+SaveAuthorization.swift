import Foundation

extension ProjectLibrary {
    func requireNoForeignPendingSave(
        at url: URL, requesting projectID: Project.ID,
        accessibleRoots: [URL], caseSensitiveNames: (URL) -> Bool?
    ) throws {
        for owner in projects where owner.id != projectID {
            for operation in owner.pendingLifecycleOperations {
                // These URLs only reserve physical paths. They never authorize access, supply
                // template eligibility, or establish completion on behalf of another project.
                var rootHints: [UUID: [URL]] = [:]
                for (id, identity) in operation.rootIdentities {
                    guard let root = owner.root(id) else { throw LifecycleError.pendingRepair }
                    let resolved = try? FolderBookmark.resolve(root.bookmark).url
                    let originalRoots = (accessibleRoots + [resolved].compactMap { $0 })
                        .filter { (try? LifecycleIdentity($0)) == identity }
                    let hints =
                        originalRoots.isEmpty ? [root.lastKnownURL] + [resolved].compactMap { $0 } : originalRoots
                    rootHints[id] = hints
                }
                let base = rootHints.compactMapValues(\.first)
                // Each path reservation is independent; enumerate alternatives for one
                // root at a time rather than multiplying equivalent-root combinations.
                let variants = rootHints.flatMap { id, hints in
                    hints.map { hint in
                        var roots = base
                        roots[id] = hint
                        return roots
                    }
                }
                for roots in variants
                where try LifecyclePath.reserves(
                    url, operation: operation, roots: roots, caseSensitiveNames: caseSensitiveNames)
                {
                    throw LifecycleRecoveryError(
                        operation: operation, moved: false, cause: LifecycleError.pendingRepair)
                }
            }
        }
    }
}
