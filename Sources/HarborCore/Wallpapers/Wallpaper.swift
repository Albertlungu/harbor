import Foundation

/// One wallpaper from Wallhaven, trimmed to the fields Harbor shows or needs.
public struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The wallpaper's page on Wallhaven, shown as its source link.
    public var page: URL
    public var full: URL
    public var thumb: URL
    public var width: Int
    public var height: Int
    public var fileSize: Int
    public var fileType: String
    /// Where the uploader says the image came from; often empty.
    public var source: String
    public var colors: [String]

    public init(id: String, page: URL, full: URL, thumb: URL, width: Int, height: Int,
                fileSize: Int = 0, fileType: String = "image/jpeg", source: String = "", colors: [String] = []) {
        self.id = id
        self.page = page
        self.full = full
        self.thumb = thumb
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.fileType = fileType
        self.source = source
        self.colors = colors
    }

    public var resolution: String { "\(width)×\(height)" }

    /// The file name used when saving the full image.
    public var fileName: String {
        let name = full.lastPathComponent
        return name.isEmpty ? "wallhaven-\(id).jpg" : name
    }

    enum CodingKeys: String, CodingKey {
        case id, page, full, thumb, width, height, fileSize, fileType, source, colors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        page = try c.decode(URL.self, forKey: .page)
        full = try c.decode(URL.self, forKey: .full)
        thumb = try c.decode(URL.self, forKey: .thumb)
        width = c(.width, 0)
        height = c(.height, 0)
        fileSize = c(.fileSize, 0)
        fileType = c(.fileType, "image/jpeg")
        source = c(.source, "")
        colors = c(.colors, [])
    }
}

/// A page of Wallhaven search results.
public struct WallpaperPage: Sendable, Equatable {
    public var items: [Wallpaper]
    public var page: Int
    public var lastPage: Int
    public var total: Int
    /// The seed a random search must repeat to page through the same order.
    public var seed: String?

    public var hasMore: Bool { page < lastPage }

    /// Decodes a `/api/v1/search` response. Entries missing a required field are skipped
    /// rather than failing the page.
    public static func decode(_ data: Data) throws -> WallpaperPage {
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        let items = raw.data.compactMap { $0.value?.wallpaper }
        return WallpaperPage(items: items, page: raw.meta?.current_page ?? 1, lastPage: raw.meta?.last_page ?? 1,
                             total: raw.meta?.total ?? items.count, seed: raw.meta?.seed)
    }

    private struct RawResponse: Decodable {
        var data: [Lenient<RawWallpaper>]
        var meta: Meta?
    }

    // Wallhaven's snake_case field names, kept as-is so the shape reads like the API docs.
    private struct Meta: Decodable {
        var current_page: Int?
        var last_page: Int?
        var total: Int?
        var seed: String?
    }

    private struct RawWallpaper: Decodable {
        var id: String
        var url: URL
        var path: URL
        var thumbs: [String: URL]
        var dimension_x: Int?
        var dimension_y: Int?
        var file_size: Int?
        var file_type: String?
        var source: String?
        var colors: [String]?

        var wallpaper: Wallpaper? {
            // The large thumb is 16:9 and sharp at grid size on Retina, so one fetch serves grid and preview.
            guard let thumb = thumbs["large"] ?? thumbs["small"] else { return nil }
            return Wallpaper(id: id, page: url, full: path, thumb: thumb, width: dimension_x ?? 0,
                             height: dimension_y ?? 0, fileSize: file_size ?? 0, fileType: file_type ?? "image/jpeg",
                             source: source ?? "", colors: colors ?? [])
        }
    }

    private struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}
