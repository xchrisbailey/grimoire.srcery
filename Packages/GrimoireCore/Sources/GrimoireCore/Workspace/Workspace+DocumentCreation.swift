import Darwin
import Foundation

public enum DocumentNamingIntent: Equatable, Sendable {
    case generated
    case edited(String)
}

public enum DocumentCreationPurpose: Sendable {
    case document
    case templateSource
}

public enum DocumentRecoveryIntent: Sendable {
    case retry
    case createEmptyOnce
}

public struct PublishedDocument: Sendable {
    public let url: URL
    /// Nil retains the legacy preview and rename experience.
    public let editorCaretUTF16: Int?
}

public struct DocumentCreationPlan: Identifiable, Sendable {
    public internal(set) var id: UUID
    public let destination: URL
    public let source: URL?
    public let assignment: FolderTemplateAssignment?
    public let suggestedStem: String
    public internal(set) var requiresNaming: Bool
    var usesSource: Bool {
        if case .useSource = assignment?.choice { return true }
        return false
    }
    let projectID: Project.ID
    let filenamePattern: String
    let purpose: DocumentCreationPurpose
    let context: DocumentCreationContext
}

public enum DocumentCreationResult {
    case cancelled
    case invalidName(DocumentNameError)
    case reviewNeeded(DocumentCreationPlan)
    case contextUnavailable(any Error)
    case sourceFailure(DocumentCreationPlan, any Error)
    case failed(any Error)
    case published(PublishedDocument)
    case alreadyPublished(PublishedDocument)
    /// Publication succeeded but access/context changed. Never retry creation or remove the output.
    case publishedButUnavailable(URL)
}

public enum DocumentNameError: Error, LocalizedError {
    case invalidStem

    public var errorDescription: String? {
        String(
            localized:
                "Enter a name without surrounding whitespace, leading dots, path separators or control characters.")
    }

    public static func validate(_ stem: String) throws {
        guard !stem.isEmpty, stem == stem.trimmingCharacters(in: .whitespacesAndNewlines),
            !stem.hasPrefix("."), !stem.contains("/"), !stem.contains("\\"),
            stem.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { throw Self.invalidStem }
    }
}

struct CreationFolderIdentity: Equatable, Sendable {
    let url: URL
    let device: Int32
    let inode: UInt64

    init(_ url: URL) throws {
        self.url = url.resolvingSymlinksInPath()
        var info = stat()
        guard stat(url.path(percentEncoded: false), &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw TemplateAssignmentError.unavailableFolder
        }
        device = info.st_dev
        inode = info.st_ino
    }
}

struct DocumentCreationContext: Equatable, Sendable {
    // The destination's chosen binding, distinct from the inherited assignment's owner.
    let owner: FileReference
    let assignment: FolderTemplateAssignment?
    let destination: CreationFolderIdentity
    let roots: [CreationFolderIdentity]
    let sourceURL: URL?
}

extension Workspace {
    public func prepareDocument(
        in destination: URL, filenamePattern: String, purpose: DocumentCreationPurpose = .document
    ) throws -> DocumentCreationPlan {
        try prepareDocument(
            in: destination, filenamePattern: filenamePattern, purpose: purpose, now: .now, calendar: .current)
    }

    func prepareDocument(
        in destination: URL, filenamePattern: String, purpose: DocumentCreationPurpose = .document,
        now: Date, calendar: Calendar
    ) throws -> DocumentCreationPlan {
        // Other windows can replace a bookmark without this workspace having received its UI update yet.
        sync()
        guard let owner = try templateReference(for: destination) else {
            throw TemplateAssignmentError.unavailableFolder
        }
        let assignment: FolderTemplateAssignment?
        if purpose == .document {
            assignment = try effectiveTemplateAssignment(for: destination)
        } else {
            assignment = nil
        }
        var source: URL?
        var requiresNaming = false
        var rootIDs = [owner.rootID]
        if case .useSource(let reference) = assignment?.choice {
            requiresNaming = true
            try assignment?.validate()
            if let root = templateRoots.first(where: { $0.id == reference.rootID })?.url {
                rootIDs.append(reference.rootID)
                source = reference.url(in: root)
            }
        }
        let roots = try rootIDs.map { id in
            guard let root = templateRoots.first(where: { $0.id == id })?.url else {
                throw TemplateAssignmentError.unavailableFolder
            }
            return try CreationFolderIdentity(root)
        }
        // Legacy subfolder creation may target a directory not made yet. Pin its nearest existing ancestor.
        var ancestor = destination
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.pathComponents.count > 1 {
            ancestor.deleteLastPathComponent()
        }
        let context = DocumentCreationContext(
            owner: owner, assignment: assignment, destination: try CreationFolderIdentity(ancestor), roots: roots,
            sourceURL: source)
        return DocumentCreationPlan(
            id: UUID(), destination: destination, source: source, assignment: assignment,
            suggestedStem: FileNaming.name(from: filenamePattern, date: now, calendar: calendar),
            requiresNaming: requiresNaming,
            projectID: projectID, filenamePattern: filenamePattern, purpose: purpose, context: context)
    }

    public func createDocument(
        _ plan: DocumentCreationPlan, naming: DocumentNamingIntent,
        confirmed: Bool = true, recovery: DocumentRecoveryIntent = .retry
    ) -> DocumentCreationResult {
        createDocument(
            plan, naming: naming, confirmed: confirmed, recovery: recovery, now: .now, calendar: .current,
            operations: DocumentCreationOperations())
    }

    func createDocument(
        _ plan: DocumentCreationPlan, naming: DocumentNamingIntent,
        confirmed: Bool = true, recovery: DocumentRecoveryIntent = .retry,
        now: Date, calendar: Calendar, operations: DocumentCreationOperations
    ) -> DocumentCreationResult {
        guard confirmed else {
            emptyOnceCreations.remove(plan.id)
            return .cancelled
        }
        if let published = publishedCreations[plan.id] { return .alreadyPublished(published) }
        guard plan.projectID == projectID else { return .contextUnavailable(TemplateAssignmentError.unavailableFolder) }
        var current: DocumentCreationPlan
        do {
            current = try prepareDocument(
                in: plan.destination, filenamePattern: plan.filenamePattern, purpose: plan.purpose,
                now: now, calendar: calendar)
        } catch { return .contextUnavailable(error) }
        current.id = plan.id
        current.requiresNaming = current.requiresNaming || plan.requiresNaming
        guard current.context == plan.context else { return .reviewNeeded(current) }
        if recovery == .createEmptyOnce { emptyOnceCreations.insert(plan.id) }
        let stem: String
        switch naming {
        case .generated: stem = current.suggestedStem
        case .edited(let entered):
            do { try DocumentNameError.validate(entered) } catch { return .invalidName(.invalidStem) }
            stem = entered
        }
        let bytes: Data
        do {
            bytes = try creationBytes(current)
        } catch { return .sourceFailure(current, error) }
        return publishDocument(current, named: stem, operations: operations) { candidate in
            ContentPlaceholders.expand(bytes, filename: candidate, date: now, calendar: calendar)
        }
    }

    private func creationBytes(_ plan: DocumentCreationPlan) throws -> Data {
        if emptyOnceCreations.contains(plan.id) { return Data() }
        guard plan.usesSource else { return Data() }
        guard let source = plan.source else { throw TemplateAssignmentError.ineligibleSource }
        return try savedTemplateBytes(at: source)
    }

    private func publishDocument(
        _ current: DocumentCreationPlan, named stem: String, operations: DocumentCreationOperations,
        content: (String) -> Data
    ) -> DocumentCreationResult {
        do {
            // No suspension: MainActor stages project mutations across the whole publication attempt.
            try validateCreationContext(current)
            try FileManager.default.createDirectory(at: current.destination, withIntermediateDirectories: true)
            var expanded = Data()
            let url = try FileOperations.createDocument(
                in: current.destination, named: stem, operations: operations,
                content: { candidate in
                    expanded = content(candidate)
                    return expanded
                },
                validate: { try self.validateCreationContext(current) })
            let caret: Int?
            if current.requiresNaming {
                guard let text = String(validating: expanded, as: UTF8.self) else {
                    return .publishedButUnavailable(url)
                }
                caret = text.utf16.count
            } else {
                caret = nil
            }
            let published = PublishedDocument(url: url, editorCaretUTF16: caret)
            publishedCreations[current.id] = published
            emptyOnceCreations.remove(current.id)
            return .published(published)
        } catch DocumentPublicationError.publishedButUnavailable(let url) {
            publishedCreations[current.id] = PublishedDocument(url: url, editorCaretUTF16: nil)
            emptyOnceCreations.remove(current.id)
            return .publishedButUnavailable(url)
        } catch { return .failed(error) }
    }

    private func validateCreationContext(_ plan: DocumentCreationPlan) throws {
        guard isActive, project != nil else { throw TemplateAssignmentError.unavailableFolder }
        for root in plan.context.roots {
            guard try CreationFolderIdentity(root.url) == root else { throw TemplateAssignmentError.unavailableFolder }
        }
        guard try CreationFolderIdentity(plan.context.destination.url) == plan.context.destination else {
            throw TemplateAssignmentError.unavailableFolder
        }
        let fresh = try prepareDocument(
            in: plan.destination, filenamePattern: plan.filenamePattern, purpose: plan.purpose,
            now: .now, calendar: .current)
        // Once a missing legacy folder has been created its nearest ancestor changes; its root/choice must not.
        guard fresh.context.owner == plan.context.owner, fresh.assignment == plan.assignment,
            fresh.context.roots == plan.context.roots, fresh.context.sourceURL == plan.context.sourceURL
        else { throw TemplateAssignmentError.unavailableFolder }
        if plan.usesSource, !emptyOnceCreations.contains(plan.id), let source = plan.source {
            _ = try eligibleTemplateReference(for: source)
        }
    }
}
