import Foundation

extension Workspace {
    /// Legacy cross-volume movement cannot prove identity continuity. Admission must not
    /// depend on whether a proposed operation happened to produce a configuration delta.
    func requireLegacyAdmission(source: URL, destination: URL) throws {
        try requireNoPendingLifecycle(at: source)
        try requireNoPendingLifecycle(at: destination.deletingLastPathComponent())
        let scopes = [source, destination.deletingLastPathComponent()]
        for operation in project?.pendingLifecycleOperations ?? [] {
            for assignment in operation.before + operation.after
            where try legacyDependency(assignment, overlaps: scopes) {
                throw LifecycleError.pendingRepair
            }
        }
        for assignment in project?.templateAssignments ?? [] where try legacyDependency(assignment, overlaps: scopes) {
            throw LifecycleError.configurationProtected
        }
    }

    private func legacyDependency(_ assignment: FolderTemplateAssignment, overlaps scopes: [URL]) throws -> Bool {
        var references = [assignment.owner]
        if case .useSource(let source) = assignment.choice { references.append(source) }
        return try references.contains { reference in
            guard let root = project?.root(reference.rootID) else { throw TemplateAssignmentError.invalidReference }
            // Last-known paths can conservatively block admission, never grant access or complete recovery.
            let rootURL = url(for: FileReference(rootID: root.id, relativePath: "")) ?? root.lastKnownURL
            let dependency = try LifecyclePath.components(reference.url(in: rootURL))
            return try scopes.contains { scope in
                let components = try LifecyclePath.components(scope)
                return components.starts(with: dependency) || dependency.starts(with: components)
            }
        }
    }
}
