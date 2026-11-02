import Foundation

public enum DocumentTemplateRepairResult {
    case cancelled
    case repaired(DocumentCreationPlan)
    /// Settings were committed; only preparation of the pending document failed.
    case savedButUnavailable(any Error)
    case reviewNeeded(DocumentCreationPlan)
    case failed(any Error)
}

extension Workspace {
    /// Confirmation covers the supplying owner's inheritance scope, not a new destination override.
    /// Persist the repair independently: subsequent cancellation or publication failure cannot undo it.
    public func repairDocumentTemplate(
        _ plan: DocumentCreationPlan, replacement: URL, confirmed: Bool = true
    ) -> DocumentTemplateRepairResult {
        guard confirmed else { return .cancelled }
        guard plan.projectID == projectID, publishedCreations[plan.id] == nil else {
            return .failed(TemplateAssignmentError.unavailableFolder)
        }
        do {
            var current = try prepareDocument(
                in: plan.destination, filenamePattern: plan.filenamePattern, purpose: plan.purpose)
            current.id = plan.id
            current.requiresNaming = current.requiresNaming || plan.requiresNaming
            guard current.context == plan.context else { return .reviewNeeded(current) }
            guard let assignment = current.assignment, current.usesSource else {
                throw TemplateAssignmentError.ineligibleSource
            }
            let reference = try eligibleTemplateReference(for: replacement)
            _ = try savedTemplateBytes(at: replacement)
            // Source I/O can outlive external folder changes. Recheck the confirmed scope before settings mutation.
            var validated = try prepareDocument(
                in: plan.destination, filenamePattern: plan.filenamePattern, purpose: plan.purpose)
            validated.id = plan.id
            validated.requiresNaming = current.requiresNaming
            guard validated.context == current.context else { return .reviewNeeded(validated) }
            try saveTemplateAssignment(
                FolderTemplateAssignment(owner: assignment.owner, choice: .useSource(reference)))
            do {
                var repaired = try prepareDocument(
                    in: plan.destination, filenamePattern: plan.filenamePattern, purpose: plan.purpose)
                repaired.id = plan.id
                repaired.requiresNaming = current.requiresNaming
                return .repaired(repaired)
            } catch { return .savedButUnavailable(error) }
        } catch { return .failed(error) }
    }
}
