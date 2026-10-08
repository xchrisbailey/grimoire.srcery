import Foundation

/// Files from Finder waiting for a window, by project, and how many windows have been
/// asked for on their behalf. A window that is about to show a project takes its files
/// instead of restoring what it last had open.
public struct PendingOpens: Equatable, Sendable {
    private var placements: [ProjectLibrary.Placement] = []
    private var requestedWindows = 0

    public init() {}

    /// Queues `placement`. Files for a project already waiting join its list.
    public mutating func add(_ placement: ProjectLibrary.Placement) {
        guard let index = placements.firstIndex(where: { $0.projectID == placement.projectID }) else {
            placements.append(placement)
            return
        }
        for url in placement.urls where !placements[index].urls.contains(url) {
            placements[index].urls.append(url)
        }
    }

    /// How many more windows to open so that each waiting project has one coming. Counts
    /// them as asked for.
    public mutating func windowsToRequest() -> Int {
        let missing = max(0, placements.count - requestedWindows)
        requestedWindows += missing
        return missing
    }

    /// What a window that is about to restore itself takes: the files waiting for the
    /// project it showed last time, or, for a new window, the files of whichever project
    /// has waited longest. A new window also counts as one that was asked for.
    public mutating func claim(preferring projectID: Project.ID?, isNew: Bool) -> ProjectLibrary.Placement? {
        if isNew { requestedWindows = max(0, requestedWindows - 1) }
        if let projectID, let index = placements.firstIndex(where: { $0.projectID == projectID }) {
            return placements.remove(at: index)
        }
        return isNew && !placements.isEmpty ? placements.removeFirst() : nil
    }
}
