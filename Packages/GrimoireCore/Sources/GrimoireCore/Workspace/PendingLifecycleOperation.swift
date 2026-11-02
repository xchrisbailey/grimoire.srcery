import Darwin
import Foundation

struct LifecycleIdentity: Codable, Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let type: UInt16

    init(_ url: URL) throws {
        var info = stat()
        guard lstat(Self.entryPath(url), &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        device = info.st_dev
        inode = info.st_ino
        type = info.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else { throw LifecycleError.unsupportedBoundary }
    }

    static func entryPath(_ url: URL) -> String {
        // A trailing directory slash makes lstat follow a symlink, defeating exact-entry evidence.
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

struct LifecycleSourceProjection: Codable, Hashable, Sendable {
    let source: FileReference
    let rootIdentity: LifecycleIdentity

    func affects(_ assignments: [FolderTemplateAssignment]) -> Bool {
        assignments.contains { assignment in
            let references = [assignment.owner] + assignment.sourceReferences
            return references.contains { reference in
                reference.rootID == source.rootID
                    && reference.relativePath.split(separator: "/")
                        .starts(with: source.relativePath.split(separator: "/"))
            }
        }
    }
}

extension FolderTemplateAssignment {
    var sourceReferences: [FileReference] {
        if case .useSource(let source) = choice { return [source] }
        return []
    }
}

struct PendingLifecycleOperation: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case relocation, trash }
    var kind: Kind = .relocation
    var trashRoots: [DestructiveRootScope]?
    let id: UUID
    let projectID: UUID
    let source: FileReference
    let destination: FileReference
    let rootIdentity: LifecycleIdentity
    let itemIdentity: LifecycleIdentity
    let sourceParentIdentity: LifecycleIdentity
    let destinationParentIdentity: LifecycleIdentity
    let before: [FolderTemplateAssignment]
    let after: [FolderTemplateAssignment]
    let destinationRootIdentity: LifecycleIdentity?
    let sourceProjections: [LifecycleSourceProjection]?

    var sourceCoordinates: [FileReference] {
        if kind == .trash { return trashCoordinates }
        return [source] + (sourceProjections ?? []).map(\.source)
    }

    var reservedReferences: [FileReference] { sourceCoordinates + (kind == .relocation ? [destination] : []) }

    var recordReferences: [FileReference] { (before + after).flatMap { [$0.owner] + $0.sourceReferences } }

    var rootIdentities: [UUID: LifecycleIdentity] {
        var identities = [source.rootID: rootIdentity]
        if kind == .trash {
            for scope in trashRoots ?? [] { if let identity = scope.identity { identities[scope.id] = identity } }
            return identities
        }
        identities[destination.rootID] = destinationRootIdentity ?? rootIdentity
        for projection in sourceProjections ?? [] { identities[projection.source.rootID] = projection.rootIdentity }
        return identities
    }

    private var trashCoordinates: [FileReference] {
        guard let originalRoot = trashRoots?.first(where: { $0.id == source.rootID }) else { return [source] }
        let parts =
            URL(filePath: originalRoot.resolvedPath).pathComponents
            + source.relativePath.split(separator: "/").map(String.init)
        // Scoped paths only deny conflicting mutations. They never prove a trash
        // outcome, grant access, or become relocation/source-ownership evidence.
        return (trashRoots ?? []).compactMap { scope in
            let rootParts = URL(filePath: scope.resolvedPath).pathComponents
            guard parts.starts(with: rootParts) else { return nil }
            return FileReference(
                rootID: scope.id, relativePath: parts.dropFirst(rootParts.count).joined(separator: "/"))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, trashRoots, id, projectID, source, destination, rootIdentity, itemIdentity
        case sourceParentIdentity, destinationParentIdentity, before, after, destinationRootIdentity, sourceProjections
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = values.contains(.kind) ? try values.decode(Kind.self, forKey: .kind) : .relocation
        trashRoots =
            values.contains(.trashRoots) ? try values.decode([DestructiveRootScope].self, forKey: .trashRoots) : nil
        id = try values.decode(UUID.self, forKey: .id)
        projectID = try values.decode(UUID.self, forKey: .projectID)
        source = try values.decode(FileReference.self, forKey: .source)
        destination = try values.decode(FileReference.self, forKey: .destination)
        rootIdentity = try values.decode(LifecycleIdentity.self, forKey: .rootIdentity)
        itemIdentity = try values.decode(LifecycleIdentity.self, forKey: .itemIdentity)
        sourceParentIdentity = try values.decode(LifecycleIdentity.self, forKey: .sourceParentIdentity)
        destinationParentIdentity = try values.decode(LifecycleIdentity.self, forKey: .destinationParentIdentity)
        before = try values.decode([FolderTemplateAssignment].self, forKey: .before)
        after = try values.decode([FolderTemplateAssignment].self, forKey: .after)
        destinationRootIdentity =
            values.contains(.destinationRootIdentity)
            ? try values.decode(LifecycleIdentity.self, forKey: .destinationRootIdentity) : nil
        sourceProjections =
            values.contains(.sourceProjections)
            ? try values.decode([LifecycleSourceProjection].self, forKey: .sourceProjections) : nil
    }

    init(
        kind: Kind = .relocation, trashRoots: [DestructiveRootScope]? = nil,
        id: UUID, projectID: UUID, source: FileReference, destination: FileReference,
        rootIdentity: LifecycleIdentity, itemIdentity: LifecycleIdentity,
        sourceParentIdentity: LifecycleIdentity, destinationParentIdentity: LifecycleIdentity,
        before: [FolderTemplateAssignment], after: [FolderTemplateAssignment],
        destinationRootIdentity: LifecycleIdentity? = nil, sourceProjections: [LifecycleSourceProjection]? = nil
    ) {
        self.kind = kind
        self.trashRoots = trashRoots
        self.id = id
        self.projectID = projectID
        self.source = source
        self.destination = destination
        self.rootIdentity = rootIdentity
        self.itemIdentity = itemIdentity
        self.sourceParentIdentity = sourceParentIdentity
        self.destinationParentIdentity = destinationParentIdentity
        self.before = before
        self.after = after
        self.destinationRootIdentity = destinationRootIdentity
        self.sourceProjections = sourceProjections
    }

    func contains(_ reference: FileReference) -> Bool {
        reservedReferences.contains { reserved in
            reference.rootID == reserved.rootID && Self.overlaps(reference.relativePath, reserved.relativePath)
        }
    }

    static func overlaps(_ left: String, _ right: String) -> Bool {
        let lhs = left.split(separator: "/")
        let rhs = right.split(separator: "/")
        return lhs.starts(with: rhs) || rhs.starts(with: lhs)
    }

    func touches(_ assignment: FolderTemplateAssignment) -> Bool {
        if contains(assignment.owner) { return true }
        if case .useSource(let source) = assignment.choice { return contains(source) }
        return false
    }

    func conflicts(with other: Self) -> Bool {
        let owners = Set((before + after).map(\.owner))
        return itemIdentity == other.itemIdentity || other.reservedReferences.contains(where: contains)
            || !(owners.isDisjoint(with: (other.before + other.after).map(\.owner)))
            || recordReferences.contains(where: other.reservesRecord)
            || other.recordReferences.contains(where: reservesRecord)
    }

    private func reservesRecord(_ reference: FileReference) -> Bool {
        reservedReferences.contains { endpoint in
            reference.rootID == endpoint.rootID
                && reference.relativePath.split(separator: "/").starts(
                    with: endpoint.relativePath.split(separator: "/"))
        }
    }

    func validate(in project: Project) throws {
        try FolderTemplateAssignment.validate(source.relativePath, allowsRoot: false)
        try FolderTemplateAssignment.validate(destination.relativePath, allowsRoot: false)
        try FolderTemplateAssignment.validate(before)
        try FolderTemplateAssignment.validate(after)
        if kind == .trash {
            try validateTrash(in: project)
            return
        }
        guard trashRoots == nil else { throw LifecycleError.invalidRecord }
        try validateSourceProjections(in: project)
        guard projectID == project.id, project.root(source.rootID) != nil, project.root(destination.rootID) != nil,
            source != destination,
            source.rootID != destination.rootID || !Self.overlaps(source.relativePath, destination.relativePath),
            source.rootID == destination.rootID || destinationRootIdentity != nil,
            destinationRootIdentity == nil || destinationRootIdentity?.type == S_IFDIR,
            source.rootID != destination.rootID || destinationRootIdentity == nil
                || destinationRootIdentity == rootIdentity,
            rootIdentity.type == S_IFDIR, sourceParentIdentity.type == S_IFDIR,
            destinationParentIdentity.type == S_IFDIR,
            itemIdentity.type == S_IFDIR || itemIdentity.type == S_IFREG,
            itemIdentity.device == sourceParentIdentity.device,
            itemIdentity.device == destinationParentIdentity.device,
            !before.isEmpty || source.rootID != destination.rootID, before.count == after.count,
            Set(before.map(\.owner)).count == before.count,
            Set(after.map(\.owner)).count == after.count,
            before.allSatisfy({ project.templateAssignments.contains($0) }),
            zip(before, after).allSatisfy({ old, new in
                var expected = old
                expected.owner = relocated(old.owner)
                if case .useSource(let source) = old.choice { expected.choice = .useSource(relocated(source)) }
                return expected != old && expected == new
            })
        else { throw LifecycleError.invalidRecord }
        try FolderTemplateAssignment.validate(project.templateAssignments.filter { !before.contains($0) } + after)
    }

    private func validateTrash(in project: Project) throws {
        guard destinationRootIdentity == nil, sourceProjections == nil,
            projectID == project.id, source == destination, project.root(source.rootID) != nil,
            rootIdentity.type == S_IFDIR, sourceParentIdentity.type == S_IFDIR,
            destinationParentIdentity == sourceParentIdentity,
            itemIdentity.type == S_IFREG || itemIdentity.type == S_IFDIR,
            !before.isEmpty, Set(before.map(\.owner)).count == before.count,
            Set(after.map(\.owner)).count == after.count,
            before.allSatisfy({ project.templateAssignments.contains($0) }),
            after.allSatisfy({ before.contains($0) }),
            let trashRoots, !trashRoots.isEmpty,
            Set(trashRoots.map(\.id)).count == trashRoots.count,
            trashRoots.contains(where: { $0.id == source.rootID && $0.identity == rootIdentity }),
            trashRoots.allSatisfy({ scope in
                guard let root = project.root(scope.id) else { return false }
                return root.bookmark == scope.bookmark && root.lastKnownPath == scope.path
                    && scope.identity?.type == S_IFDIR && scope.resolvedPath.hasPrefix("/")
            })
        else { throw LifecycleError.invalidRecord }
        func parts(_ reference: FileReference) -> [String]? {
            guard let scope = trashRoots.first(where: { $0.id == reference.rootID }) else { return nil }
            return URL(filePath: scope.resolvedPath).pathComponents
                + reference.relativePath.split(separator: "/").map(String.init)
        }
        guard let sourceParts = parts(source) else { throw LifecycleError.invalidRecord }
        func inside(_ reference: FileReference) -> Bool { parts(reference)?.starts(with: sourceParts) == true }
        guard before.filter({ !after.contains($0) }).allSatisfy({ inside($0.owner) }),
            after.allSatisfy({ assignment in
                guard !inside(assignment.owner), case .useSource(let source) = assignment.choice else { return false }
                return inside(source)
            })
        else { throw LifecycleError.invalidRecord }
    }

    func relocated(_ reference: FileReference) -> FileReference {
        guard kind == .relocation else { return reference }
        guard let coordinate = sourceCoordinates.first(where: { $0.rootID == reference.rootID }) else {
            return reference
        }
        return Self.relocated(reference, from: coordinate, to: destination)
    }

    private func validateSourceProjections(in project: Project) throws {
        let projections = sourceProjections ?? []
        guard sourceProjections == nil || !projections.isEmpty,
            Set(projections.map { $0.source.rootID }).count == projections.count
        else { throw LifecycleError.invalidRecord }
        for projection in projections {
            try FolderTemplateAssignment.validate(projection.source.relativePath, allowsRoot: false)
            guard projection.source.rootID != source.rootID, project.root(projection.source.rootID) != nil,
                projection.rootIdentity.type == S_IFDIR, projection.affects(before),
                projection.source.rootID != destination.rootID
                    || projection.rootIdentity == (destinationRootIdentity ?? rootIdentity)
            else { throw LifecycleError.invalidRecord }
        }
    }

    static func relocated(_ reference: FileReference, from source: FileReference, to destination: FileReference)
        -> FileReference
    {
        let parts = reference.relativePath.split(separator: "/")
        let prefix = source.relativePath.split(separator: "/")
        guard reference.rootID == source.rootID, parts.starts(with: prefix) else { return reference }
        return FileReference(
            rootID: destination.rootID,
            relativePath: (destination.relativePath.split(separator: "/") + parts.dropFirst(prefix.count)).joined(
                separator: "/"))
    }
}

extension Project {
    func validateLifecycleOperations() throws {
        guard Set(pendingLifecycleOperations.map(\.id)).count == pendingLifecycleOperations.count else {
            throw LifecycleError.invalidRecord
        }
        for (index, operation) in pendingLifecycleOperations.enumerated() {
            try operation.validate(in: self)
            guard
                !pendingLifecycleOperations.dropFirst(index + 1).contains(where: {
                    operation.conflicts(with: $0)
                })
            else { throw LifecycleError.invalidRecord }
        }
    }
}

public enum LifecycleError: Error, LocalizedError, Equatable {
    case conflict, pendingRepair, unsupportedBoundary, invalidRecord, configurationProtected, unknownNameEquivalence
    case crossVolumeConfiguration
    /// A bound folder holding the item or its destination can't be reached, so ownership can't be decided.
    case containingFolderUnavailable(String)
    /// The recorded folder was found at a different path while a move still needs repair. Carries its original path.
    case movedWhileRepairing(String)

    public var errorDescription: String? {
        switch self {
        case .movedWhileRepairing(let path):
            String(
                localized: """
                    This folder was moved while a move still needs repair. Nothing changed. \
                    Put it back at “\(path)”, then grant access again.
                    """
            )
        case .containingFolderUnavailable(let name):
            String(
                localized: """
                    The bound folder “\(name)” is unavailable, so this move can't be checked. Nothing changed. \
                    Grant access to “\(name)” again, then retry.
                    """
            )
        case .crossVolumeConfiguration:
            String(
                localized: """
                    Folders with template choices can't be moved to another volume. Nothing changed. \
                    In Content Template…, choose Inherit for the choices on this folder, its subfolders, \
                    or the destination, and for any folder that uses a file inside this one as its template. \
                    Remove inactive choices with Remove Assignment under Content Templates. Then move it again.
                    """
            )
        case .unknownNameEquivalence:
            String(
                localized:
                    "Folder names may conflict. Restore volume access or resolve the destination choices, then retry.")
        case .configurationProtected:
            String(
                localized:
                    "Template choices or source references block this operation. Files and settings are unchanged."
            )
        case .conflict:
            String(localized: "The destination has folder template choices. Resolve the conflict before moving.")
        case .pendingRepair:
            String(
                localized:
                    "A move needs repair. Restore the original at its shown source or destination, then retry."
            )
                + "\n" + String(localized: "Retry only checks the filesystem; it never moves or reverses files.")
        case .unsupportedBoundary:
            String(
                localized:
                    "This move crosses an unsupported filesystem or bound-root boundary. Nothing changed."
            )
        case .invalidRecord:
            String(localized: "Invalid folder move recovery record. Repair the project settings before retrying.")
        }
    }
}

struct LifecycleRecoveryError: LocalizedError {
    let operation: PendingLifecycleOperation
    let moved: Bool
    let cause: any Error

    var errorDescription: String? {
        if operation.kind == .trash {
            return String(
                localized:
                    "A trash operation has an unknown outcome. Review its recorded configuration removal."
            )
                + "\n" + String(localized: "Retry never moves or restores files.")
                + "\n[" + operation.source.rootID.uuidString + "]/" + operation.source.relativePath
                + "\n" + cause.localizedDescription
        }
        let status =
            moved
            ? String(localized: "The item moved, but its project changes are still pending.")
            : LifecycleError.pendingRepair.localizedDescription
        return status + "\n[" + operation.source.rootID.uuidString + "]/" + operation.source.relativePath
            + " → [" + operation.destination.rootID.uuidString + "]/" + operation.destination.relativePath
            + "\n" + cause.localizedDescription
    }
}
