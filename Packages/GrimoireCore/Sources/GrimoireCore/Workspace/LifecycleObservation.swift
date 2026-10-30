import Foundation

struct LifecycleObservedRoot {
    let url: URL
    let identity: LifecycleIdentity
}

struct LifecycleObservation {
    let source: URL
    let destination: URL
    let itemIdentity: LifecycleIdentity
    let sourceParentIdentity: LifecycleIdentity
    let destinationParentIdentity: LifecycleIdentity
    let roots: [LifecycleObservedRoot]

    init(source: URL, destination: URL, roots: [URL]) throws {
        self.source = source
        self.destination = destination
        itemIdentity = try LifecycleIdentity(source)
        sourceParentIdentity = try LifecycleIdentity(source.deletingLastPathComponent())
        destinationParentIdentity = try LifecycleIdentity(destination.deletingLastPathComponent())
        self.roots = try roots.map { LifecycleObservedRoot(url: $0, identity: try LifecycleIdentity($0)) }
    }

    init(operation: PendingLifecycleOperation, root: URL) {
        source = operation.source.url(in: root)
        destination = operation.destination.url(in: root)
        itemIdentity = operation.itemIdentity
        sourceParentIdentity = operation.sourceParentIdentity
        destinationParentIdentity = operation.destinationParentIdentity
        roots = [LifecycleObservedRoot(url: root, identity: operation.rootIdentity)]
    }

    func completed() throws -> Bool {
        for root in roots {
            guard try LifecycleIdentity(root.url) == root.identity else { throw LifecycleError.pendingRepair }
        }
        guard try LifecycleIdentity(source.deletingLastPathComponent()) == sourceParentIdentity,
            try LifecycleIdentity(destination.deletingLastPathComponent()) == destinationParentIdentity
        else { throw LifecycleError.pendingRepair }
        let atSource = try Self.identity(at: source)
        let atDestination = try Self.identity(at: destination)
        if atSource == itemIdentity, atDestination == nil { return false }
        if atSource == nil, atDestination == itemIdentity { return true }
        throw LifecycleError.pendingRepair
    }

    private static func identity(at url: URL) throws -> LifecycleIdentity? {
        guard try hasExactEntry(url) else { return nil }
        return try LifecycleIdentity(url)
    }

    static func hasExactEntry(_ url: URL) throws -> Bool {
        // Directory entries distinguish case-only renames on case-insensitive volumes.
        try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .contains(url.lastPathComponent)
    }
}

struct LifecyclePreparation {
    let operation: PendingLifecycleOperation?
    let observation: LifecycleObservation
    var isLegacy = false
}
