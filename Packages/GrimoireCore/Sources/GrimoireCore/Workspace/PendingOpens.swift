import Foundation

/// Files from Finder waiting for a window, by project. A window that is about to show a
/// project takes its files instead of restoring what it last had open.
public struct PendingOpens: Equatable, Sendable {
    private var placements: [ProjectLibrary.Placement] = []

    public init() {}

    /// How many projects are waiting for a window.
    public var count: Int { placements.count }

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

    /// Removes and returns the files waiting for `projectID`.
    public mutating func take(_ projectID: Project.ID) -> ProjectLibrary.Placement? {
        guard let index = placements.firstIndex(where: { $0.projectID == projectID }) else { return nil }
        return placements.remove(at: index)
    }

    /// Removes and returns the project that has waited longest.
    public mutating func takeFirst() -> ProjectLibrary.Placement? {
        placements.isEmpty ? nil : placements.removeFirst()
    }
}
