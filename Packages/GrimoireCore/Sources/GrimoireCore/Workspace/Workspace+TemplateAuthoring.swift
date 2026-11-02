import Foundation

public struct TemplateAuthoringPlan: Sendable {
    let creation: DocumentCreationPlan
    let owner: DocumentCreationPlan
    let previousAssignment: FolderTemplateAssignment?
}

public enum TemplateAuthoringResult {
    case cancelled
    case failed(any Error)
    case assigned(PublishedDocument)
    /// The ordinary source remains on disk. Repair assignment separately; never recreate it.
    case unassigned(PublishedDocument, any Error)
}

public enum TemplateAuthoringError: Error, LocalizedError {
    case contextChanged

    public var errorDescription: String? {
        String(localized: "Template authoring details changed. Choose the location and folder again.")
    }
}

extension Workspace {
    public func prepareTemplateSource(in destination: URL, assigningTo folder: URL) throws -> TemplateAuthoringPlan {
        let creation = try prepareDocument(in: destination, filenamePattern: "Template", purpose: .templateSource)
        let previous = try templateAssignment(for: folder)
        let owner = try prepareDocument(in: folder, filenamePattern: "Template", purpose: .templateSource)
        // Authoring chooses an existing bound directory, not legacy creation's optional subfolder.
        _ = try CreationFolderIdentity(destination)
        return TemplateAuthoringPlan(creation: creation, owner: owner, previousAssignment: previous)
    }

    public func createTemplateSource(
        _ plan: TemplateAuthoringPlan, named stem: String, confirmed: Bool = true
    ) -> TemplateAuthoringResult {
        createTemplateSource(plan, named: stem, confirmed: confirmed, operations: DocumentCreationOperations())
    }

    func createTemplateSource(
        _ plan: TemplateAuthoringPlan, named stem: String, confirmed: Bool = true,
        operations: DocumentCreationOperations
    ) -> TemplateAuthoringResult {
        guard confirmed else { return .cancelled }
        if let completed = templateAuthoringResults[plan.creation.id] { return completed }
        do { try validateAuthoringOwner(plan) } catch { return .failed(error) }
        let published: PublishedDocument
        switch createDocument(
            plan.creation, naming: .edited(stem), now: .now, calendar: .current, operations: operations)
        {
        case .published(let source):
            var adapted = source
            adapted.editorCaretUTF16 = 0
            published = adapted
        case .publishedButUnavailable(let url):
            var source =
                publishedCreations[plan.creation.id]
                ?? PublishedDocument(id: plan.creation.id, url: url, editorCaretUTF16: nil, verified: false)
            source.editorCaretUTF16 = 0
            let result = TemplateAuthoringResult.unassigned(
                source, TemplateAuthoringError.contextChanged)
            templateAuthoringResults[plan.creation.id] = result
            return result
        case .invalidName(let error): return .failed(error)
        case .failed(let error), .contextUnavailable(let error), .sourceFailure(_, let error): return .failed(error)
        case .cancelled: return .cancelled
        case .reviewNeeded, .alreadyPublished: return .failed(TemplateAuthoringError.contextChanged)
        }
        let result: TemplateAuthoringResult
        do {
            try validateAuthoringOwner(plan)
            try assignTemplate(published.url, to: plan.owner.destination)
            result = .assigned(published)
        } catch {
            result = .unassigned(published, error)
        }
        // A failed settings commit is terminal for source creation too: retrying must not allocate another file.
        templateAuthoringResults[plan.creation.id] = result
        return result
    }

    private func validateAuthoringOwner(_ plan: TemplateAuthoringPlan) throws {
        let current = try prepareDocument(
            in: plan.owner.destination, filenamePattern: "Template", purpose: .templateSource)
        guard plan.owner.projectID == projectID, current.context == plan.owner.context,
            try templateAssignment(for: plan.owner.destination) == plan.previousAssignment
        else { throw TemplateAuthoringError.contextChanged }
    }
}
