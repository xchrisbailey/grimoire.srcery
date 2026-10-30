import Darwin
import Foundation

public struct LifecycleResult {
    /// Non-nil whenever the filesystem move succeeded, even if its settings commit failed.
    public let movedURL: URL?
    public let error: (any Error)?
}

struct LifecycleOperations {
    var rename: (URL, String) throws -> URL = { try FileOperations.rename($0, to: $1) }
    var move: (URL, URL) throws -> URL = { try FileOperations.move($0, into: $1) }
}

extension Workspace {
    public var hasPendingLifecycleOperations: Bool { !(project?.pendingLifecycleOperations.isEmpty ?? true) }

    public var lifecycleRepairURLs: [URL] {
        (project?.pendingLifecycleOperations ?? []).flatMap { operation in
            // Last-known paths are only hints for manual repair in Finder, never reconciliation evidence.
            let root =
                folders.first { $0.id == operation.source.rootID }?.url
                ?? project?.root(operation.source.rootID)?.lastKnownURL
            return root.map { [operation.source.url(in: $0), operation.destination.url(in: $0)] } ?? []
        }
    }

    public func rename(_ url: URL, to name: String) -> LifecycleResult {
        do {
            let destination = try FileOperations.renameDestination(url, to: name)
            return relocate(url, to: destination) { try lifecycleOperations.rename(url, name) }
        } catch { return LifecycleResult(movedURL: nil, error: error) }
    }

    public func move(_ url: URL, into folder: URL) -> LifecycleResult {
        relocate(url, to: folder.appending(path: url.lastPathComponent)) {
            try lifecycleOperations.move(url, folder)
        }
    }

    private func relocate(_ source: URL, to destination: URL, perform: () throws -> URL) -> LifecycleResult {
        var moved: URL?
        var pending: PendingLifecycleOperation?
        do {
            sync()
            try validateActiveTemplateOwners()
            try requireNoPendingLifecycle(at: source)
            try requireNoPendingLifecycle(at: destination)
            if source.standardizedFileURL == destination.standardizedFileURL {
                return LifecycleResult(movedURL: source, error: nil)
            }
            let operation = try prepareRelocation(source, to: destination)
            pending = operation
            if let operation {
                try library.update(projectID) { $0.pendingLifecycleOperations.append(operation) }
            }
            do {
                moved = try perform()
            } catch {
                // Even a failed filesystem call can leave an uncertain outcome. Inspect identities,
                // never reverse or replay it; failed cleanup persistence must retain the intent.
                reconcileLifecycleOperations()
                throw error
            }
            if let operation {
                guard try observedCompletion(of: operation) else { throw LifecycleError.pendingRepair }
                try finishRelocation(operation, completed: true)
            }
            refreshAll()
            return LifecycleResult(movedURL: moved, error: nil)
        } catch {
            refreshAll()
            let failure: any Error
            if let pending, project?.pendingLifecycleOperations.contains(pending) == true {
                failure = LifecycleRecoveryError(operation: pending, moved: moved != nil, cause: error)
            } else {
                failure = error
            }
            return LifecycleResult(movedURL: moved, error: failure)
        }
    }

    private func prepareRelocation(_ source: URL, to destination: URL) throws -> PendingLifecycleOperation? {
        guard let project, let from = try lifecycleReference(for: source),
            let parent = try lifecycleReference(for: destination.deletingLastPathComponent()),
            !from.relativePath.isEmpty
        else { throw LifecycleError.unsupportedBoundary }
        let to = Self.destinationReference(parent: parent, name: destination.lastPathComponent)
        let root = try rootURL(from.rootID)
        try requireMovableSubtree(source)
        try requireVacantDestination(destination, moving: source)
        var before: [FolderTemplateAssignment] = []
        var after: [FolderTemplateAssignment] = []
        for assignment in project.templateAssignments {
            try assignment.validate()
            var updated = assignment
            if assignment.state == .unresolved {
                // Inactive aliases are stored choices, not evidence of the live target's identity.
                updated.owner = PendingLifecycleOperation.relocated(assignment.owner, from: from, to: to)
            } else {
                updated.owner = try relocatedReference(assignment.owner, source: source, destination: destination)
            }
            if case .useSource(let reference) = assignment.choice {
                updated.choice = .useSource(try relocatedReference(reference, source: source, destination: destination))
            }
            if assignment != updated {
                before.append(assignment)
                after.append(updated)
            }
        }
        let remaining = project.templateAssignments.filter { !before.contains($0) }
        for assignment in remaining {
            guard let ownerURL = self.url(for: assignment.owner) else { continue }
            if try LifecyclePath.reference(rootID: from.rootID, root: destination, url: ownerURL) != nil {
                throw LifecycleError.conflict
            }
        }
        if before.isEmpty { return nil }
        guard from.rootID == to.rootID else { throw LifecycleError.unsupportedBoundary }
        try FolderTemplateAssignment.validate(remaining + after)
        let operation = PendingLifecycleOperation(
            id: UUID(), projectID: projectID, source: from, destination: to,
            rootIdentity: try LifecycleIdentity(root), itemIdentity: try LifecycleIdentity(source),
            sourceParentIdentity: try LifecycleIdentity(source.deletingLastPathComponent()),
            destinationParentIdentity: try LifecycleIdentity(destination.deletingLastPathComponent()),
            before: before, after: after)
        try operation.validate(in: project)
        return operation
    }

    private func requireMovableSubtree(_ source: URL) throws {
        // Physical root relocation and separately bound descendants belong to different tickets.
        for bound in templateRoots {
            guard let url = bound.url else { continue }
            if try LifecyclePath.reference(rootID: bound.id, root: source, url: url) != nil {
                throw LifecycleError.unsupportedBoundary
            }
        }
    }

    private func requireVacantDestination(_ destination: URL, moving source: URL) throws {
        var info = stat()
        guard lstat(destination.path(percentEncoded: false), &info) == 0 else {
            guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return
        }
        // Only the original entry's case alias may already answer the prospective name.
        if source.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased(),
            try !hasExactEntry(destination),
            let identity = try? LifecycleIdentity(destination), try identity == LifecycleIdentity(source),
            try LifecycleIdentity(source.deletingLastPathComponent())
                == LifecycleIdentity(destination.deletingLastPathComponent())
        {
            return
        }
        throw FileOperationError.alreadyExists(destination.lastPathComponent)
    }

    private static func destinationReference(parent: FileReference, name: String, suffix: String = "") -> FileReference
    {
        FileReference(
            rootID: parent.rootID,
            relativePath: ([parent.relativePath, name, suffix].filter { !$0.isEmpty }).joined(separator: "/"))
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
        let movedURL = suffix.url(in: destination)
        guard
            let parent = try LifecyclePath.reference(
                rootID: reference.rootID, root: root,
                url: destination.deletingLastPathComponent()),
            try lifecycleReference(for: movedURL)?.rootID == reference.rootID
        else { throw LifecycleError.unsupportedBoundary }
        // Resolve the parent, not the prospective leaf: on case-insensitive volumes the
        // old item can already answer the new spelling before the rename happens.
        return Self.destinationReference(
            parent: parent, name: destination.lastPathComponent, suffix: suffix.relativePath)
    }

    private func rootURL(_ id: UUID) throws -> URL {
        guard let root = templateRoots.first(where: { $0.id == id })?.url else { throw LifecycleError.pendingRepair }
        return root
    }

    private func lifecycleReference(for url: URL) throws -> FileReference? {
        var best: (reference: FileReference, depth: Int)?
        for folder in templateRoots {
            guard let root = folder.url,
                let reference = try LifecyclePath.reference(rootID: folder.id, root: root, url: url)
            else { continue }
            let depth = try LifecyclePath.components(root).count
            if depth > (best?.depth ?? -1) { best = (reference, depth) }
        }
        return best?.reference
    }

    /// Runs after bound-root access is resolved. It only commits an observed outcome; it never moves files.
    public func reconcileLifecycleOperations() {
        lastError = nil
        for operation in project?.pendingLifecycleOperations ?? [] {
            do {
                try finishRelocation(operation, completed: observedCompletion(of: operation))
            } catch { lastError = LifecycleRecoveryError(operation: operation, moved: false, cause: error) }
        }
    }

    private func observedCompletion(of operation: PendingLifecycleOperation) throws -> Bool {
        let root = try rootURL(operation.source.rootID)
        let source = operation.source.url(in: root)
        let destination = operation.destination.url(in: root)
        guard try LifecycleIdentity(root) == operation.rootIdentity,
            try LifecycleIdentity(source.deletingLastPathComponent()) == operation.sourceParentIdentity,
            try LifecycleIdentity(destination.deletingLastPathComponent()) == operation.destinationParentIdentity
        else { throw LifecycleError.pendingRepair }
        let atSource = try observedIdentity(source)
        let atDestination = try observedIdentity(destination)
        if atSource == operation.itemIdentity, atDestination == nil { return false }
        if atSource == nil, atDestination == operation.itemIdentity { return true }
        throw LifecycleError.pendingRepair
    }

    private func observedIdentity(_ url: URL) throws -> LifecycleIdentity? {
        guard try hasExactEntry(url) else { return nil }
        return try LifecycleIdentity(url)
    }

    private func hasExactEntry(_ url: URL) throws -> Bool {
        // Exact names distinguish a case-only rename on a case-insensitive volume.
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        return names.contains(url.lastPathComponent)
    }

    private func finishRelocation(_ operation: PendingLifecycleOperation, completed: Bool) throws {
        try library.finishLifecycleOperation(operation, in: projectID, completed: completed)
    }

    func requireNoPendingLifecycle(at url: URL) throws {
        for operation in project?.pendingLifecycleOperations ?? [] {
            guard let root = self.url(for: FileReference(rootID: operation.source.rootID, relativePath: "")) else {
                continue
            }
            if let reference = try LifecyclePath.reference(rootID: operation.source.rootID, root: root, url: url),
                operation.contains(reference)
            {
                throw LifecycleError.pendingRepair
            }
        }
    }

    /// Out-of-scope destructive operations must not silently orphan project configuration.
    public func requireUnconfiguredLifecycleItem(_ url: URL) throws {
        try requireNoPendingLifecycle(at: url)
        for assignment in project?.templateAssignments ?? [] {
            let references =
                [assignment.owner]
                + {
                    if case .useSource(let source) = assignment.choice { return [source] }
                    return []
                }()
            for reference in references {
                guard let referenced = self.url(for: reference) else { continue }
                if FileReference(rootID: reference.rootID, rootURL: url, url: referenced) != nil {
                    throw LifecycleError.configurationProtected
                }
            }
        }
    }
}
