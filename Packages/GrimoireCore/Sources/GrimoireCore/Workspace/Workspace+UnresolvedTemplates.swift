import Foundation

extension Workspace {
    public var unresolvedTemplateAssignments: [FolderTemplateAssignment] {
        project?.templateAssignments.filter { $0.state == .unresolved } ?? []
    }

    /// Called on activation, completed scans and explicit retry, never during view evaluation.
    /// An unreadable root/ancestor is not evidence of deletion. Pending intent gets first refusal.
    public func refreshTemplateAssignments() {
        guard isActive else { return }
        sync()
        refreshTemplateRootLocations()
        reconcileLifecycleOperations()
        refreshTemplateRootLocations()
        var missing: [FolderTemplateAssignment] = []
        for assignment in project?.templateAssignments ?? [] where assignment.state == .active {
            do {
                try requireAvailableTemplateDependency(assignment)
                if try templateOwnerIsMissing(assignment.owner) { missing.append(assignment) }
            } catch {
                // Access and ambiguous pending evidence leave the choice untouched for explicit retry.
                if case LifecycleError.pendingRepair = error { continue }
                lastError = error
            }
        }
        guard !missing.isEmpty else { return }
        do {
            try library.update(projectID, caseSensitiveNames: lifecycleOperations.caseSensitiveNames) { project in
                for index in project.templateAssignments.indices
                where missing.contains(project.templateAssignments[index]) {
                    project.templateAssignments[index].state = .unresolved
                }
            }
        } catch { lastError = error }
    }

    private func templateOwnerIsMissing(_ owner: FileReference) throws -> Bool {
        guard let root = templateRoots.first(where: { $0.id == owner.rootID })?.url,
            let pinned = templateRootIdentities[owner.rootID],
            try readableTemplateRoot(owner.rootID, at: root) == pinned
        else { return false }
        var current = root.resolvingSymlinksInPath()
        var missing = false
        for name in owner.relativePath.split(separator: "/").map(String.init) {
            let names = try FileManager.default.contentsOfDirectory(atPath: current.path)
            let matches = try names.filter {
                try LifecyclePath.namesEqual($0, name, caseSensitive: lifecycleOperations.caseSensitiveNames(current))
            }
            guard matches.count <= 1 else { throw LifecycleError.unknownNameEquivalence }
            guard let match = matches.first else {
                missing = true
                break
            }
            current.append(path: match)
            guard try LifecyclePath.reference(rootID: owner.rootID, root: root, url: current) != nil else {
                throw TemplateAssignmentError.invalidReference
            }
            // Listing each ancestor distinguishes denied access and dangling links from an absent entry.
            _ = try FileManager.default.contentsOfDirectory(atPath: current.path)
        }
        guard try readableTemplateRoot(owner.rootID, at: root) == pinned else { return false }
        return missing
    }

    private func readableTemplateRoot(_ id: FolderRoot.ID, at url: URL) throws -> LifecycleIdentity? {
        guard let root = project?.root(id) else { return nil }
        let resolved = try FolderBookmark.resolve(root.bookmark).url.resolvingSymlinksInPath()
        guard resolved.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        let identity = try LifecycleIdentity(resolved)
        _ = try FileManager.default.contentsOfDirectory(atPath: resolved.path)
        return identity
    }
}
