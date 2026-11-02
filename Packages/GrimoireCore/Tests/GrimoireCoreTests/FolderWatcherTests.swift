import Foundation
import Testing

@testable import GrimoireCore

@Suite struct FolderWatcherTests {
    @Test func seesFilesCreatedOutsideTheApp() async throws {
        let scratch = try Scratch()
        let (events, continuation) = AsyncStream<[String]>.makeStream()
        let watcher = FolderWatcher(url: scratch.url, latency: 0.05) { continuation.yield($0) }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        try scratch.file("new.md")
        let saw = await firstEvent(in: events, matching: { $0.contains { $0.hasSuffix("new.md") } })
        #expect(saw)
    }

    /// Replacing a watcher while events arrive is what `OpenDocument.watch()` does on every
    /// open. The stream's callback used to reach a freed watcher.
    @Test func survivesBeingDestroyedUnderAStreamOfChanges() async throws {
        let scratch = try Scratch()
        let writing = Flag()
        let writer = Task.detached {
            var count = 0
            while !writing.isSet {
                count += 1
                try? Data("\(count)".utf8).write(to: scratch.url.appending(path: "f\(count % 20).md"))
                try? await Task.sleep(for: .milliseconds(1))
            }
        }

        var stopped: [(tally: Tally, atStop: Int)] = []
        var delivered = 0
        for round in 0..<120 {
            let tally = Tally()
            var watcher: FolderWatcher? = FolderWatcher(url: scratch.url, latency: 0.001) { _ in tally.hit() }
            try await Task.sleep(for: .milliseconds(round % 7))
            if round.isMultiple(of: 2) {
                watcher?.stop()
                stopped.append((tally, tally.count))
            }
            // Odd rounds skip `stop()` and rely on `deinit`.
            watcher = nil
            delivered += tally.count
        }
        writing.set()
        await writer.value

        try await Task.sleep(for: .milliseconds(200))
        #expect(stopped.allSatisfy { $0.tally.count == $0.atStop })
        #expect(delivered > 0, "the writer should have produced events for the watchers to race")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var hits = 0
    var count: Int { lock.withLock { hits } }
    func hit() { lock.withLock { hits += 1 } }
}
