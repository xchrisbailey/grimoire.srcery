import Darwin
import Foundation

public struct LifecycleResult {
    /// The identity-verified original item's destination, including when final settings persistence fails.
    public let movedURL: URL?
    /// The pre-existing unconfigured cross-volume route. This is not an identity-verified handoff.
    public let legacyMovedURL: URL?
    public let error: (any Error)?

    init(movedURL: URL?, error: (any Error)?, legacyMovedURL: URL? = nil) {
        self.movedURL = movedURL
        self.legacyMovedURL = legacyMovedURL
        self.error = error
    }
}

struct LifecycleOperations {
    var rename: (URL, String) throws -> URL = { try FileOperations.rename($0, to: $1) }
    var move: (URL, URL) throws -> URL = { try FileOperations.move($0, into: $1) }
    var caseSensitiveNames: (URL) -> Bool? = {
        (try? $0.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames
    }
    var isSameVolume: (URL, URL) throws -> Bool = {
        try LifecycleIdentity($0).device == LifecycleIdentity($1).device
    }
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
                _ = try LifecycleIdentity(source)
                return LifecycleResult(movedURL: source, error: nil)
            }
            let preparation = try prepareRelocation(source, to: destination)
            if preparation.isLegacy {
                let legacy = try perform()
                refreshAll()
                return LifecycleResult(movedURL: nil, error: nil, legacyMovedURL: legacy)
            }
            let operation = preparation.operation
            pending = operation
            if let operation {
                try library.update(projectID) { $0.pendingLifecycleOperations.append(operation) }
            }
            do {
                _ = try perform()
            } catch {
                // Even a failed filesystem call can leave an uncertain outcome. Inspect identities,
                // never reverse or replay it; failed cleanup persistence must retain the intent.
                if (try? preparation.observation.completed()) == true {
                    moved = preparation.observation.destination
                }
                reconcileLifecycleOperations()
                throw error
            }
            guard try preparation.observation.completed() else { throw LifecycleError.pendingRepair }
            moved = preparation.observation.destination
            if let operation {
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

    private func prepareRelocation(_ source: URL, to destination: URL) throws -> LifecyclePreparation {
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
            let updated = try relocatedAssignment(
                assignment, from: from, to: to, source: source, destination: destination)
            if assignment != updated {
                before.append(assignment)
                after.append(updated)
            }
        }
        let remaining = project.templateAssignments.filter { !before.contains($0) }
        try validateDestinationChoices(remaining, destination: destination)
        let observation = try LifecycleObservation(
            source: source, destination: destination,
            roots: [root, rootURL(to.rootID)])
        if try !lifecycleOperations.isSameVolume(source, destination.deletingLastPathComponent())
            || observation.itemIdentity.device != observation.destinationParentIdentity.device
        {
            guard from.rootID != to.rootID, observation.roots[0].identity != observation.roots[1].identity,
                before.isEmpty
            else { throw LifecycleError.unsupportedBoundary }
            try requireLegacyAdmission(source: source, destination: destination)
            return LifecyclePreparation(operation: nil, observation: observation, isLegacy: true)
        }
        if before.isEmpty { return LifecyclePreparation(operation: nil, observation: observation) }
        guard from.rootID == to.rootID else { throw LifecycleError.unsupportedBoundary }
        try FolderTemplateAssignment.validate(remaining + after)
        let operation = PendingLifecycleOperation(
            id: UUID(), projectID: projectID, source: from, destination: to,
            rootIdentity: observation.roots[0].identity, itemIdentity: observation.itemIdentity,
            sourceParentIdentity: observation.sourceParentIdentity,
            destinationParentIdentity: observation.destinationParentIdentity,
            before: before, after: after)
        try operation.validate(in: project)
        guard !project.pendingLifecycleOperations.contains(where: { $0.conflicts(with: operation) }) else {
            throw LifecycleError.pendingRepair
        }
        return LifecyclePreparation(operation: operation, observation: observation)
    }

    private func relocatedAssignment(
        _ assignment: FolderTemplateAssignment, from: FileReference, to: FileReference,
        source: URL, destination: URL
    ) throws -> FolderTemplateAssignment {
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
        return updated
    }

    private func validateDestinationChoices(_ assignments: [FolderTemplateAssignment], destination: URL) throws {
        let caseSensitive = lifecycleOperations.caseSensitiveNames(destination.deletingLastPathComponent())
        for assignment in assignments {
            guard let ownerURL = url(for: assignment.owner) else { continue }
            if try LifecyclePath.destinationContains(ownerURL, destination: destination, caseSensitive: caseSensitive) {
                throw LifecycleError.conflict
            }
        }
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
            try !LifecycleObservation.hasExactEntry(destination),
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
        return try LifecycleObservation(operation: operation, root: root).completed()
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
