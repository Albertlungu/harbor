import AppKit
import HarborCore
import ImageIO
import SwiftUI

/// Downloads a site's icon; the apple-touch-icon is preferred because it is larger than the favicon.
enum FaviconFetcher {
    static func fetch(for url: URL) async -> Data? {
        var candidates: [URL] = []
        if let page = await pageIcon(for: url) { candidates.append(page) }
        candidates += StorageLogic.faviconCandidates(for: url)
        for candidate in candidates {
            if let data = await download(candidate, limit: 2_000_000), isImage(data) { return data }
        }
        return nil
    }

    private static func pageIcon(for url: URL) async -> URL? {
        guard let host = url.host, let root = URL(string: "\(url.scheme ?? "https")://\(host)/"),
              let data = await download(root, limit: 262_144) else { return nil }
        return StorageLogic.appleTouchIcon(inHTML: String(decoding: data, as: UTF8.self), base: root)
    }

    private static func download(_ url: URL, limit: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= limit else { return nil }
        return data
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}

/// Memory and disk cache for site icons, keyed by host.
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private let memory = NSCache<NSString, NSImage>()
    private var failed: Set<String> = []

    func image(for url: URL, directory: URL) async -> NSImage? {
        guard let host = url.host else { return nil }
        if let cached = memory.object(forKey: host as NSString) { return cached }
        let safe = host.replacingOccurrences(of: "/", with: "_")
        let file = directory.appendingPathComponent(safe + ".icon")
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            memory.setObject(image, forKey: host as NSString)
            return image
        }
        // A site without an icon is only asked once per launch.
        guard !failed.contains(host) else { return nil }
        guard let data = await FaviconFetcher.fetch(for: url), let image = NSImage(data: data) else {
            failed.insert(host)
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file)
        memory.setObject(image, forKey: host as NSString)
        return image
    }
}

/// Opens a web address from the dock.
struct LinkWidget: View {
    @Environment(AppModel.self) private var model
    let item: DockItem
    let widget: WidgetConfig
    let dock: Dock
    let size: CGSize
    let state: DockViewState

    @State private var favicon: NSImage?

    private var url: URL? { StorageLogic.normalizedURL(widget.string("url", "")) }
    private var source: String { widget.string("iconSource", "favicon") }
    private var title: String {
        let custom = widget.string("title", "")
        return custom.isEmpty ? (url?.host ?? "Link") : custom
    }

    var body: some View {
        let side = min(size.width, size.height)
        let showTitle = widget.bool("showTitle", false)
        let tile = showTitle ? side * 0.74 : side
        VStack(spacing: 1) {
            icon(side: tile)
            if showTitle {
                Text(title).font(.system(size: max(8, side * 0.17))).lineLimit(1).frame(width: side)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url { NSWorkspace.shared.open(url) } else { model.openItemSettings(item.id, in: dock.id) }
        }
        .task(id: source == "favicon" ? url?.host : nil) {
            guard source == "favicon", let url else { favicon = nil; return }
            favicon = await FaviconCache.shared.image(for: url, directory: model.file.directory.appendingPathComponent("Favicons"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(url?.host.map { "Opens \($0)" } ?? "Needs a web address")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func icon(side: CGFloat) -> some View {
        let radius = side * 0.24
        switch source {
        case "symbol":
            tile(side: side, radius: radius) {
                Image(systemName: widget.string("symbol", "link"))
                    .font(.system(size: side * 0.46))
                    .foregroundStyle(colorSetting(widget, "symbolColor") ?? Color.primary)
            }
        case "file":
            if let image = NSImage(contentsOfFile: (widget.string("iconFile", "") as NSString).expandingTildeInPath) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: side, height: side)
            } else {
                fallback(side: side, radius: radius)
            }
        default:
            if let favicon {
                tile(side: side, radius: radius) {
                    Image(nsImage: favicon).resizable().interpolation(.high).scaledToFit().padding(side * 0.18)
                }
            } else {
                fallback(side: side, radius: radius)
            }
        }
    }

    private func fallback(side: CGFloat, radius: CGFloat) -> some View {
        tile(side: side, radius: radius) {
            Image(systemName: "globe").font(.system(size: side * 0.46)).foregroundStyle(Tokens.textMuted)
        }
    }

    private func tile<Inner: View>(side: CGFloat, radius: CGFloat, @ViewBuilder _ inner: () -> Inner) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary)
            inner()
        }
        .frame(width: side, height: side)
    }
}
