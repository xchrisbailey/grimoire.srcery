import Foundation

extension Workspace {
    func sourceProjectionCandidates(
        for assignments: [FolderTemplateAssignment], source: URL, from: FileReference, identity: LifecycleIdentity
    ) throws -> [LifecycleSourceProjection] {
        let referencedRoots = Set(assignments.flatMap { [$0.owner] + $0.sourceReferences }.map(\.rootID))
        var projections: [LifecycleSourceProjection] = []
        for bound in templateRoots where bound.id != from.rootID && referencedRoots.contains(bound.id) {
            guard let root = bound.url,
                let coordinate = try LifecyclePath.reference(rootID: bound.id, root: root, url: source)
            else { continue }
            let projected = coordinate.url(in: root)
            // Equal inodes alone could be unrelated hardlinks. Coordinates must project
            // onto the same original path within their own accessible bound roots.
            guard try LifecyclePath.components(projected) == LifecyclePath.components(source),
                try LifecycleIdentity(projected) == identity
            else { throw LifecycleError.pendingRepair }
            projections.append(LifecycleSourceProjection(source: coordinate, rootIdentity: try LifecycleIdentity(root)))
        }
        return projections
    }

    func relocatedAssignments(
        _ assignments: [FolderTemplateAssignment], coordinates: [FileReference], to: FileReference,
        source: URL, destination: URL
    ) throws -> (before: [FolderTemplateAssignment], after: [FolderTemplateAssignment]) {
        var before: [FolderTemplateAssignment] = []
        var after: [FolderTemplateAssignment] = []
        for assignment in assignments {
            let updated = try relocatedAssignment(
                assignment, coordinates: coordinates, to: to, source: source, destination: destination)
            if assignment != updated {
                before.append(assignment)
                after.append(updated)
            }
        }
        return (before, after)
    }

    private func relocatedAssignment(
        _ assignment: FolderTemplateAssignment, coordinates: [FileReference], to: FileReference,
        source: URL, destination: URL
    ) throws -> FolderTemplateAssignment {
        try assignment.validate()
        var updated = assignment
        if assignment.state == .unresolved {
            // Inactive aliases are stored choices, not evidence of the live target's identity.
            if let coordinate = coordinates.first(where: { $0.rootID == assignment.owner.rootID }) {
                updated.owner = PendingLifecycleOperation.relocated(assignment.owner, from: coordinate, to: to)
            }
        } else {
            updated.owner = try relocatedReference(assignment.owner, source: source, destination: destination)
        }
        if case .useSource(let reference) = assignment.choice {
            updated.choice = .useSource(try relocatedReference(reference, source: source, destination: destination))
        }
        return updated
    }

    private func relocatedReference(_ reference: FileReference, source: URL, destination: URL) throws -> FileReference {
        guard let root = templateRoots.first(where: { $0.id == reference.rootID })?.url else { return reference }
        let url = reference.url(in: root)
        guard let suffix = try LifecyclePath.reference(rootID: reference.rootID, root: source, url: url) else {
            return reference
        }
        guard let canonical = try LifecyclePath.reference(rootID: reference.rootID, root: root, url: url),
            canonical == reference
        else { throw TemplateAssignmentError.invalidReference }
        guard let parent = try lifecycleReference(for: destination.deletingLastPathComponent())
        else { throw LifecycleError.unsupportedBoundary }
        // Resolve the parent, not the prospective leaf: on case-insensitive volumes the
        // old item can already answer the new spelling before the rename happens.
        return Self.destinationReference(
            parent: parent, name: destination.lastPathComponent, suffix: suffix.relativePath)
    }
}
