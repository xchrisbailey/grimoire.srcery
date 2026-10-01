import Foundation

#if os(macOS)
import CoreServices
#endif

/// Calls back when anything under a folder changes, including edits made outside the
/// app (Finder, git, another editor).
///
/// macOS uses an FSEvents stream, which sees every change. iOS has no FSEvents, so it
/// presents the folder with `NSFilePresenter` and sees coordinated changes (Files, other
/// apps, iCloud).
public final class FolderWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (_ changedPaths: [String]) -> Void

    public let url: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "computer.srcery.grimoire.folder-watcher")
    private let lock = NSLock()
    #if os(macOS)
    private var stream: FSEventStreamRef?
    #else
    private var presenter: Presenter?
    #endif

    /// `latency` coalesces bursts of changes (a git checkout, a save that writes a temp
    /// file then renames it) into one callback.
    public init(url: URL, latency: TimeInterval = 0.15, handler: @escaping Handler) {
        self.url = url
        self.handler = handler
        start(latency: latency)
    }

    deinit {
        stop()
    }

    public func stop() {
        lock.withLock {
            #if os(macOS)
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
            #else
            if let presenter {
                NSFileCoordinator.removeFilePresenter(presenter)
                self.presenter = nil
            }
            #endif
        }
    }

    fileprivate func deliver(_ paths: [String]) {
        handler(paths)
    }

    #if os(macOS)
    private func start(latency: TimeInterval) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            watcher.deliver(changed)
        }
        // No kFSEventStreamCreateFlagWatchRoot: it opens every parent folder to watch for the
        // root moving, and under the sandbox opening a parent like ~/Documents blocks on a
        // privacy check, which froze the app at launch. A moved root shows up as a stale
        // bookmark instead.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, [url.path(percentEncoded: false)] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.withLock { self.stream = stream }
    }
    #else
    private func start(latency: TimeInterval) {
        let presenter = Presenter(url: url, watcher: self)
        NSFileCoordinator.addFilePresenter(presenter)
        lock.withLock { self.presenter = presenter }
    }

    private final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
        let presentedItemURL: URL?
        let presentedItemOperationQueue: OperationQueue
        weak var watcher: FolderWatcher?

        init(url: URL, watcher: FolderWatcher) {
            presentedItemURL = url
            presentedItemOperationQueue = OperationQueue()
            presentedItemOperationQueue.maxConcurrentOperationCount = 1
            self.watcher = watcher
        }

        func presentedSubitemDidChange(at url: URL) {
            watcher?.deliver([url.path(percentEncoded: false)])
        }

        func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
            watcher?.deliver([oldURL.path(percentEncoded: false), newURL.path(percentEncoded: false)])
        }

        func presentedItemDidChange() {
            guard let url = presentedItemURL else { return }
            watcher?.deliver([url.path(percentEncoded: false)])
        }
    }
    #endif
}
