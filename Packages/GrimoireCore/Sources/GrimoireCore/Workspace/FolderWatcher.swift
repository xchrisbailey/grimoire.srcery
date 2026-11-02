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
    private let delivery: Delivery
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
        self.delivery = Delivery(handler)
        start(latency: latency)
    }

    deinit {
        stop()
    }

    public func stop() {
        // Closes the gate first, so a callback already running on the queue finishes before
        // this returns and none starts afterwards, whatever the stream does next.
        delivery.close()
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

    #if !os(macOS)
    fileprivate func deliver(_ paths: [String]) {
        delivery.deliver(paths)
    }
    #endif

    /// What an FSEvents callback reaches. It never references the watcher, so a callback that
    /// outlives the watcher (`FSEventStreamStop` doesn't wait for one already running) only
    /// touches this object, which the stream keeps alive through its context callbacks.
    private final class Delivery: @unchecked Sendable {
        private let handler: Handler
        // Recursive so a handler may call `stop()`. Held across the handler so `close()` waits
        // for a running delivery; handlers must not block on the thread that calls `stop()`.
        private let lock = NSRecursiveLock()
        private var isClosed = false

        init(_ handler: @escaping Handler) {
            self.handler = handler
        }

        func close() {
            lock.withLock { isClosed = true }
        }

        func deliver(_ paths: [String]) {
            lock.withLock {
                guard !isClosed else { return }
                handler(paths)
            }
        }
    }

    #if os(macOS)
    private func start(latency: TimeInterval) {
        // The stream retains `delivery` for as long as it can call back, and releases it when
        // it is released.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(delivery).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Delivery>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Delivery>.fromOpaque(info).release()
            },
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let delivery = Unmanaged<Delivery>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self)
            let changed = (0..<count).compactMap { array[$0] as? String }
            delivery.deliver(changed)
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
