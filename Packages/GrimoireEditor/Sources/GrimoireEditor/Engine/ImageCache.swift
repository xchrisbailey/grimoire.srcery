import CoreGraphics
import Foundation
import ImageIO

/// Decoded images for previews under image lines, loaded off the main thread.
@MainActor
public final class ImageCache {
    public static let shared = ImageCache()

    private var images: [URL: CGImage] = [:]
    private var failed: Set<URL> = []
    private var loading: [URL: [(CGImage?) -> Void]] = [:]

    public init() {}

    /// The image if it's already loaded.
    public func image(for url: URL) -> CGImage? { images[url] }

    /// Loads `url` if it isn't loaded yet, then calls `completion` on the main actor.
    /// Files that fail to load aren't retried.
    public func load(_ url: URL, completion: @escaping (CGImage?) -> Void) {
        if let image = images[url] { return completion(image) }
        if failed.contains(url) { return completion(nil) }
        if loading[url] != nil {
            loading[url]?.append(completion)
            return
        }
        loading[url] = [completion]
        Task.detached(priority: .utility) {
            let image = Self.decode(url)
            await MainActor.run {
                if let image { self.images[url] = image } else { self.failed.insert(url) }
                for waiter in self.loading.removeValue(forKey: url) ?? [] { waiter(image) }
            }
        }
    }

    /// Forgets `url`, so a changed file is read again.
    public func invalidate(_ url: URL) {
        images[url] = nil
        failed.remove(url)
    }

    private nonisolated static func decode(_ url: URL) -> CGImage? {
        guard url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // Previews never need more than a couple thousand pixels.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2000,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
