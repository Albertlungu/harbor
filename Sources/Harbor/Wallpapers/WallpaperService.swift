import AppKit
import HarborCore
import ImageIO

enum WallpaperError: LocalizedError {
    case busy
    case server(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .busy: "Wallhaven asked us to slow down. Try again in a minute."
        case .server(let code): "Wallhaven didn't answer (error \(code))."
        case .unreadable: "Wallhaven sent something Harbor couldn't read."
        }
    }
}

/// Talks to Wallhaven and keeps a small disk cache of thumbnails. Holds no state that
/// costs anything while the browser is closed: the session is idle and the cache is files.
enum WallpaperService {
    /// Few connections per host doubles as the concurrent fetch limit; extra requests wait
    /// in the session's queue, and a cancelled task leaves it without being fetched.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        // Thumbnails are cached as files below, and searches should always be fresh.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Harbor/0.1"]
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static let thumbnailDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Harbor/WallpaperThumbnails", isDirectory: true)
    static let cacheLimit = 150 * 1024 * 1024

    static let downloadDirectory: URL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Harbor Wallpapers", isDirectory: true)

    static let memory = ThumbnailMemory()

    // MARK: Search

    static func search(_ query: WallpaperQuery) async throws -> WallpaperPage {
        let (data, response) = try await session.data(from: query.url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw WallpaperError.busy }
        guard status == 200 else { throw WallpaperError.server(status) }
        do { return try WallpaperPage.decode(data) } catch { throw WallpaperError.unreadable }
    }

    // MARK: Thumbnails

    /// A thumbnail decoded at no more than `maxPixels` on its long side, from memory, the
    /// disk cache or the network, in that order. Returns nil on failure or cancellation.
    static func thumbnail(_ url: URL, maxPixels: Int) async -> NSImage? {
        if let image = memory.image(for: url) { return image }
        let file = thumbnailDirectory.appendingPathComponent(WallpaperCacheKey.fileName(for: url))
        var data = try? Data(contentsOf: file)
        if data != nil {
            // The modification date stands in for last use when the cache is trimmed.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        } else {
            guard let (fetched, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
            try? fetched.write(to: file, options: .atomic)
            data = fetched
        }
        guard !Task.isCancelled, let data, let image = downsample(data, maxPixels: maxPixels) else { return nil }
        memory.store(image, for: url)
        return image
    }

    private static func downsample(_ data: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Deletes the least recently used thumbnails past the size limit.
    static func trimCache() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: thumbnailDirectory, includingPropertiesForKeys: keys) else { return }
        let files = urls.compactMap { url -> CachedFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return CachedFile(name: url.lastPathComponent, size: values.fileSize ?? 0,
                              lastUsed: values.contentModificationDate ?? .distantPast)
        }
        for name in WallpaperCacheTrim.evictions(files, limit: cacheLimit) {
            try? fm.removeItem(at: thumbnailDirectory.appendingPathComponent(name))
        }
    }

    // MARK: Full images

    /// Saves the full image into the Harbor Wallpapers folder in Pictures, reusing a copy
    /// that is already there. This is the only place a full-size image is fetched.
    static func download(_ wallpaper: Wallpaper) async throws -> URL {
        let target = downloadDirectory.appendingPathComponent(wallpaper.fileName)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let (temp, response) = try await session.download(from: wallpaper.full)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw WallpaperError.busy }
        guard status == 200 else { throw WallpaperError.server(status) }
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }

    /// Sets the desktop picture of the given screens.
    @MainActor
    static func apply(_ file: URL, to screens: [NSScreen], scaling: WallpaperScaling) throws {
        let imageScaling: NSImageScaling = switch scaling {
        case .fill, .fit: .scaleProportionallyUpOrDown
        case .stretch: .scaleAxesIndependently
        case .center: .scaleNone
        }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSNumber(value: imageScaling.rawValue),
            .allowClipping: NSNumber(value: scaling == .fill),
        ]
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: options)
        }
    }

    /// Pixel sizes of the connected screens, used to match aspect ratios.
    @MainActor
    static var screenSizes: [CGSize] {
        NSScreen.screens.map { CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor) }
    }
}

/// Decoded thumbnails kept while the browser is open. NSCache evicts under memory pressure.
final class ThumbnailMemory: @unchecked Sendable {
    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
    func removeAll() { cache.removeAllObjects() }
}
