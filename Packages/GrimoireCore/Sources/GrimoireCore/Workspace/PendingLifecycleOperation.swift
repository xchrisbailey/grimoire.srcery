import Darwin
import Foundation

struct LifecycleIdentity: Codable, Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let type: UInt16

    init(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        device = info.st_dev
        inode = info.st_ino
        type = info.st_mode & S_IFMT
        guard type == S_IFDIR || type == S_IFREG else { throw LifecycleError.unsupportedBoundary }
    }
}

struct PendingLifecycleOperation: Codable, Hashable, Sendable {
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

    func contains(_ reference: FileReference) -> Bool {
        reference.rootID == source.rootID
            && (Self.overlaps(reference.relativePath, source.relativePath)
                || Self.overlaps(reference.relativePath, destination.relativePath))
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
        return contains(other.source) || contains(other.destination)
            || !(owners.isDisjoint(with: (other.before + other.after).map(\.owner)))
    }

    func validate(in project: Project) throws {
        try FolderTemplateAssignment.validate(source.relativePath, allowsRoot: false)
        try FolderTemplateAssignment.validate(destination.relativePath, allowsRoot: false)
        try FolderTemplateAssignment.validate(before)
        try FolderTemplateAssignment.validate(after)
        guard projectID == project.id, project.root(source.rootID) != nil,
            source.rootID == destination.rootID, source != destination,
            !Self.overlaps(source.relativePath, destination.relativePath),
            rootIdentity.type == S_IFDIR, sourceParentIdentity.type == S_IFDIR,
            destinationParentIdentity.type == S_IFDIR,
            itemIdentity.type == S_IFDIR || itemIdentity.type == S_IFREG,
            !before.isEmpty, before.count == after.count,
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

    func relocated(_ reference: FileReference) -> FileReference {
        Self.relocated(reference, from: source, to: destination)
    }

    static func relocated(_ reference: FileReference, from source: FileReference, to destination: FileReference)
        -> FileReference
    {
        let parts = reference.relativePath.split(separator: "/")
        let prefix = source.relativePath.split(separator: "/")
        guard reference.rootID == source.rootID, parts.starts(with: prefix) else { return reference }
        return FileReference(
            rootID: source.rootID,
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

public enum LifecycleError: Error, LocalizedError {
    case conflict, pendingRepair, unsupportedBoundary, invalidRecord, configurationProtected, unknownNameEquivalence

    public var errorDescription: String? {
        switch self {
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
                    "Move within one bound folder, not across bindings or a bound root. Nothing changed."
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
        let status =
            moved
            ? String(localized: "The item moved, but its project changes are still pending.")
            : LifecycleError.pendingRepair.localizedDescription
        return status + "\n[" + operation.source.rootID.uuidString + "]/" + operation.source.relativePath
            + " → " + operation.destination.relativePath + "\n" + cause.localizedDescription
    }
}
