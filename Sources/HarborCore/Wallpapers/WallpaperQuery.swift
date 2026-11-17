import Foundation

public enum WallpaperSorting: String, Codable, CaseIterable, Sendable {
    case relevance, top, latest, random

    public var title: String {
        switch self {
        case .relevance: "Relevance"
        case .top: "Top"
        case .latest: "Latest"
        case .random: "Random"
        }
    }

    var apiValue: String {
        switch self {
        case .relevance: "relevance"
        case .top: "toplist"
        case .latest: "date_added"
        case .random: "random"
        }
    }
}

/// The smallest size a result may have.
public enum WallpaperMinimum: String, Codable, CaseIterable, Sendable {
    case any, hd, qhd, uhd4k, uhd5k

    public var title: String {
        switch self {
        case .any: "Any Size"
        case .hd: "1080p and Up"
        case .qhd: "1440p and Up"
        case .uhd4k: "4K and Up"
        case .uhd5k: "5K and Up"
        }
    }

    var apiValue: String? {
        switch self {
        case .any: nil
        case .hd: "1920x1080"
        case .qhd: "2560x1440"
        case .uhd4k: "3840x2160"
        case .uhd5k: "5120x2880"
        }
    }
}

/// Aspect ratios Wallhaven accepts in its `ratios` filter.
public enum WallpaperRatio: String, Codable, CaseIterable, Sendable {
    case r16x9 = "16x9", r16x10 = "16x10", r21x9 = "21x9", r32x9 = "32x9", r3x2 = "3x2", r4x3 = "4x3", r5x4 = "5x4"

    public var value: Double {
        let parts = rawValue.split(separator: "x").compactMap { Double($0) }
        return parts[0] / parts[1]
    }

    /// The listed ratio closest to a screen of the given pixel size.
    public static func nearest(width: Double, height: Double) -> WallpaperRatio {
        let target = max(width, height) / max(min(width, height), 1)
        return allCases.min { abs($0.value - target) < abs($1.value - target) }!
    }

    /// The distinct ratios for a set of screens, in a stable order.
    public static func matching(screens: [CGSize]) -> [WallpaperRatio] {
        let found = Set(screens.map { nearest(width: $0.width, height: $0.height) })
        return allCases.filter(found.contains)
    }
}

/// Wallhaven's fixed colour palette; the `colors` filter accepts only these.
public enum WallpaperPalette {
    public static let colors: [String] = [
        "660000", "990000", "cc0000", "cc3333", "ea4c88", "993399", "663399", "333399", "0066cc", "0099cc",
        "66cccc", "77cc33", "669900", "336600", "666600", "999900", "cccc33", "ffff00", "ffcc33", "ff9900",
        "ff6600", "cc6633", "996633", "663300", "000000", "999999", "cccccc", "ffffff", "424153",
    ]
}

public enum WallpaperSeason: String, Codable, CaseIterable, Sendable {
    case winter, spring, summer, autumn

    public var title: String { rawValue.capitalized }

    /// The meteorological season for a month (1...12) in the northern hemisphere.
    public static func of(month: Int) -> WallpaperSeason {
        switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }

    public static func of(_ date: Date, calendar: Calendar = .current) -> WallpaperSeason {
        of(month: calendar.component(.month, from: date))
    }

    /// Hand-picked searches that suit the season. The first is the default; the rest are
    /// offered as chips. Wallhaven has no OR operator, so each theme is its own search.
    public var themes: [String] {
        switch self {
        case .winter: ["snow landscape", "winter forest", "frozen lake", "aurora", "snowy mountains", "christmas lights"]
        case .spring: ["spring", "cherry blossom", "flower field", "green meadow", "tulips", "rain"]
        case .summer: ["beach", "tropical", "summer", "sunset ocean", "lavender field", "palm trees"]
        case .autumn: ["autumn forest", "fall foliage", "autumn", "misty forest", "pumpkins", "autumn road"]
        }
    }
}

/// What the browser shows: a free search or one season's collection.
public enum WallpaperCollection: Hashable, Sendable {
    case library
    case currentSeason
    case season(WallpaperSeason)
    case favourites

    /// The concrete season, with the current one resolved against `date`.
    public func season(on date: Date, calendar: Calendar = .current) -> WallpaperSeason? {
        switch self {
        case .currentSeason: WallpaperSeason.of(date, calendar: calendar)
        case .season(let s): s
        case .library, .favourites: nil
        }
    }
}

/// One Wallhaven search request. Always safe-for-work: purity is never configurable.
public struct WallpaperQuery: Hashable, Sendable {
    public var text: String = ""
    public var minimum: WallpaperMinimum = .uhd4k
    public var ratios: [WallpaperRatio] = []
    public var color: String?
    public var sorting: WallpaperSorting = .relevance
    /// Wallhaven category bits: general, anime, people. People is left out of the library.
    public var categories: String = "110"
    public var page: Int = 1
    public var seed: String?

    public init(text: String = "", minimum: WallpaperMinimum = .uhd4k, ratios: [WallpaperRatio] = [],
                color: String? = nil, sorting: WallpaperSorting = .relevance, categories: String = "110") {
        self.text = text
        self.minimum = minimum
        self.ratios = ratios
        self.color = color
        self.sorting = sorting
        self.categories = categories
    }

    public static let endpoint = URL(string: "https://wallhaven.cc/api/v1/search")!

    public var url: URL {
        var items: [URLQueryItem] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        items.append(URLQueryItem(name: "categories", value: categories))
        items.append(URLQueryItem(name: "purity", value: "100"))
        // Relevance means nothing without search text, so an empty search shows the top list instead.
        let sort: WallpaperSorting = trimmed.isEmpty && sorting == .relevance ? .top : sorting
        items.append(URLQueryItem(name: "sorting", value: sort.apiValue))
        if sort == .top { items.append(URLQueryItem(name: "topRange", value: "1y")) }
        if let atleast = minimum.apiValue { items.append(URLQueryItem(name: "atleast", value: atleast)) }
        if !ratios.isEmpty { items.append(URLQueryItem(name: "ratios", value: ratios.map(\.rawValue).joined(separator: ","))) }
        if let color { items.append(URLQueryItem(name: "colors", value: color)) }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        if sort == .random, let seed { items.append(URLQueryItem(name: "seed", value: seed)) }
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = items
        return components.url!
    }
}

public enum WallpaperCacheKey {
    /// A flat, stable file name for a thumbnail URL, such as `lg-p8-p8zy3m.jpg`. Built
    /// from the path so the same image keys the same way whichever host serves it.
    public static func fileName(for url: URL) -> String {
        let parts = url.pathComponents.filter { $0 != "/" }
        let name = parts.joined(separator: "-")
        let safe = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-._".unicodeScalars.contains($0) ? Character($0) : "_" }
        return safe.isEmpty ? "thumb" : String(safe)
    }
}

public struct CachedFile: Sendable, Equatable {
    public var name: String
    public var size: Int
    public var lastUsed: Date

    public init(name: String, size: Int, lastUsed: Date) {
        self.name = name
        self.size = size
        self.lastUsed = lastUsed
    }
}

public enum WallpaperCacheTrim {
    /// The least recently used files to delete so the rest fit within `limit` bytes.
    public static func evictions(_ files: [CachedFile], limit: Int) -> [String] {
        var total = files.reduce(0) { $0 + $1.size }
        var out: [String] = []
        for file in files.sorted(by: { $0.lastUsed < $1.lastUsed }) where total > limit {
            out.append(file.name)
            total -= file.size
        }
        return out
    }
}
