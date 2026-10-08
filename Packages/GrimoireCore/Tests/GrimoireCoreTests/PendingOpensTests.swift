import Foundation
import Testing

@testable import GrimoireCore

@Suite struct PendingOpensTests {
    private let first = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/a.md")])
    private let second = ProjectLibrary.Placement(projectID: UUID(), urls: [URL(filePath: "/tmp/b.md")])

    @Test func aNewWindowTakesTheProjectThatHasWaitedLongest() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(second)
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == second)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
    }

    @Test func aRestoredWindowTakesOnlyItsOwnProject() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(second)
        #expect(pending.claim(preferring: UUID(), isNew: false) == nil)
        #expect(pending.claim(preferring: nil, isNew: false) == nil)
        #expect(pending.claim(preferring: second.projectID, isNew: false) == second)
        #expect(pending.claim(preferring: second.projectID, isNew: false) == nil)
        #expect(pending.claim(preferring: first.projectID, isNew: false) == first)
    }

    @Test func filesForAWaitingProjectJoinItsList() {
        var pending = PendingOpens()
        pending.add(first)
        pending.add(.init(projectID: first.projectID, urls: [URL(filePath: "/tmp/a.md"), URL(filePath: "/tmp/c.md")]))
        #expect(pending.windowsToRequest() == 1)
        #expect(pending.claim(preferring: nil, isNew: true)?.urls.map(\.lastPathComponent) == ["a.md", "c.md"])
    }

    @Test func oneWindowIsRequestedPerWaitingProject() {
        var pending = PendingOpens()
        #expect(pending.windowsToRequest() == 0)
        pending.add(first)
        pending.add(second)
        #expect(pending.windowsToRequest() == 2)
        #expect(pending.windowsToRequest() == 0)

        // The windows asked for take what waits; nothing more is asked for.
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == second)
        #expect(pending.windowsToRequest() == 0)

        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
    }

    @Test func aNewWindowThatWasNeverAskedForDoesNotMakeTheCountNegative() {
        var pending = PendingOpens()
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
    }

    @Test func aWindowTakenByAnotherNewWindowIsNotRequestedTwice() {
        var pending = PendingOpens()
        pending.add(first)
        #expect(pending.windowsToRequest() == 1)
        // The user opened a window first; it took the files, and the one asked for arrives empty.
        #expect(pending.claim(preferring: nil, isNew: true) == first)
        #expect(pending.claim(preferring: nil, isNew: true) == nil)
        pending.add(second)
        #expect(pending.windowsToRequest() == 1)
    }
}
