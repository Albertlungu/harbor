import AppKit
import QuickLookThumbnailing

/// Quick Look thumbnails for the folder browser, generated lazily as cells appear and kept in a
/// small cache keyed by path, size and modification date so an edited file gets a fresh one.
@MainActor
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func key(_ url: URL, _ side: CGFloat, _ modified: Date?) -> NSString {
        "\(url.path)|\(Int(side))|\(modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }

    static func cached(_ url: URL, side: CGFloat, modified: Date?) -> NSImage? {
        cache.object(forKey: key(url, side, modified))
    }

    /// Calls back on the main actor with the thumbnail, or not at all when Quick Look has none.
    static func load(_ url: URL, side: CGFloat, modified: Date?, completion: @escaping @MainActor (NSImage) -> Void) {
        let cacheKey = key(url, side, modified)
        if let image = cache.object(forKey: cacheKey) {
            completion(image)
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let size = representation?.contentRect.size ?? CGSize(width: side, height: side)
            DispatchQueue.main.async {
                let image = NSImage(cgImage: cgImage, size: size)
                cache.setObject(image, forKey: cacheKey)
                completion(image)
            }
        }
    }
}
