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

    func completed(caseSensitiveNames: (URL) -> Bool? = LifecyclePath.volumeCaseSensitiveNames) throws -> Bool {
        for root in roots {
            guard try LifecycleIdentity(root.url) == root.identity else { throw LifecycleError.pendingRepair }
        }
        guard try LifecycleIdentity(source.deletingLastPathComponent()) == sourceParentIdentity,
            try LifecycleIdentity(destination.deletingLastPathComponent()) == destinationParentIdentity
        else { throw LifecycleError.pendingRepair }
        let sourceNames = caseSensitiveNames(source.deletingLastPathComponent())
        let destinationNames = caseSensitiveNames(destination.deletingLastPathComponent())
        let atSource = try Self.entry(at: source, caseSensitive: sourceNames)
        let atDestination = try Self.entry(at: destination, caseSensitive: destinationNames)
        if atSource?.identity == itemIdentity, atDestination == nil { return false }
        if atSource == nil, atDestination?.identity == itemIdentity { return true }
        // Exact spelling can select a case-only outcome only after both lookups prove
        // they refer to the same original entry, never an unrelated occupied alias.
        guard sourceParentIdentity == destinationParentIdentity, sourceNames == destinationNames,
            try LifecyclePath.namesEqual(
                source.lastPathComponent, destination.lastPathComponent,
                caseSensitive: sourceNames),
            let atSource, let atDestination, atSource.identity == itemIdentity,
            atDestination.identity == itemIdentity, atSource.name == atDestination.name
        else { throw LifecycleError.pendingRepair }
        if atSource.name == source.lastPathComponent, atSource.name != destination.lastPathComponent { return false }
        if atSource.name == destination.lastPathComponent, atSource.name != source.lastPathComponent { return true }
        throw LifecycleError.pendingRepair
    }

    private struct Entry: Equatable {
        let name: String
        let identity: LifecycleIdentity
    }

    private static func entry(at url: URL, caseSensitive: Bool?) throws -> Entry? {
        let parent = url.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        let matches = try names.filter {
            try LifecyclePath.namesEqual(
                $0, url.lastPathComponent,
                caseSensitive: caseSensitive)
        }
        guard matches.count <= 1 else { throw LifecycleError.pendingRepair }
        guard let name = matches.first else { return nil }
        return Entry(name: name, identity: try LifecycleIdentity(parent.appending(path: name)))
    }

    static func hasExactEntry(_ url: URL) throws -> Bool {
        // Only vacancy preflight uses exact spelling; recovery must inspect all equivalent entries.
        try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .contains(url.lastPathComponent)
    }
}

struct LifecyclePreparation {
    let operation: PendingLifecycleOperation?
    let observation: LifecycleObservation
    var isLegacy = false
}
