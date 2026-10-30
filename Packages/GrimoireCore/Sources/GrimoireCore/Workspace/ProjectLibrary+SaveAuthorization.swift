import Foundation

extension ProjectLibrary {
    func requireNoForeignPendingSave(
        at url: URL, requesting projectID: Project.ID,
        accessibleRoots: [URL], caseSensitiveNames: (URL) -> Bool?
    ) throws {
        for owner in projects where owner.id != projectID {
            for operation in owner.pendingLifecycleOperations {
                guard let root = owner.root(operation.source.rootID) else { throw LifecycleError.pendingRepair }
                // These URLs only reserve physical paths. They never authorize access, supply
                // template eligibility, or establish completion on behalf of another project.
                let resolved = try? FolderBookmark.resolve(root.bookmark).url
                let originalRoots = (accessibleRoots + [resolved].compactMap { $0 })
                    .filter { (try? LifecycleIdentity($0)) == operation.rootIdentity }
                let hints = originalRoots.isEmpty ? [root.lastKnownURL] + [resolved].compactMap { $0 } : originalRoots
                for hint in hints
                where try LifecyclePath.reserves(
                    url, operation: operation, in: hint, caseSensitiveNames: caseSensitiveNames)
                {
                    throw LifecycleRecoveryError(
                        operation: operation, moved: false, cause: LifecycleError.pendingRepair)
                }
            }
        }
    }
}
