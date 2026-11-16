import AppKit
import HarborCore

/// Icons for dock items, with a small cache and custom icon support.
@MainActor
enum IconProvider {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for item: DockItem, library: [IconAsset], iconsDirectory: URL) -> NSImage {
        if let id = item.customIconID, let custom = customIcon(id, library: library, directory: iconsDirectory) {
            return custom
        }
        guard let path = item.path else { return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil)! }
        return icon(forPath: path)
    }

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 256, height: 256)
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    static func customIcon(_ id: UUID, library: [IconAsset], directory: URL) -> NSImage? {
        guard let asset = library.first(where: { $0.id == id }) else { return nil }
        let key = "custom:\(asset.fileName)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(asset.fileName)) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func invalidate(path: String) { cache.removeObject(forKey: path as NSString) }
}
