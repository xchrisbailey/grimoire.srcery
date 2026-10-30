import GrimoireCore
import SwiftUI

extension FileActions {
    func unbind(_ folder: BoundFolder, from workspace: Workspace) {
        do {
            destructivePlan = try workspace.prepareUnbind(folder.id)
            destructiveNotice = nil
        } catch { self.error = error }
    }

    func confirmDestructiveOperation(workspace: Workspace) {
        guard let plan = destructivePlan, willPerformDestructiveOperation?(plan) ?? false else { return }
        do {
            switch try workspace.confirmDestructiveOperation(plan) {
            case .completed:
                destructivePlan = nil
                if plan.action == .unbind { didUnbind?() }
            case .trashed:
                destructivePlan = nil
                didTrash?(plan.item)
            case .cancelled:
                destructivePlan = nil
            case .reviewNeeded(let updated):
                destructivePlan = updated
                destructiveNotice = String(
                    localized: "The affected configuration changed. Review it, then confirm again.")
            }
        } catch {
            if let failure = error as? TrashRecoveryError {
                destructivePlan = nil
                if failure.originalItemVerified { didTrash?(plan.item) }
            }
            destructiveNotice = error.localizedDescription
            self.error = error
        }
    }
}
