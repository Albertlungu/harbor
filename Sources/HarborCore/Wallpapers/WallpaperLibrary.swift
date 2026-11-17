import Foundation

/// Favourites and wallpaper preferences, stored as wallpapers.json beside the config.
public struct WallpaperLibrary: Codable, Equatable, Sendable {
    public struct Favourite: Codable, Equatable, Sendable {
        public var wallpaper: Wallpaper
        /// The season collection it was saved from, so seasonal changes can prefer it.
        public var season: Season?

        public init(wallpaper: Wallpaper, season: Season?) {
            self.wallpaper = wallpaper
            self.season = season
        }
    }

    public var favourites: [Favourite] = []
    public var changeWithSeasons = false
    public var scaling: WallpaperScaling = .fill
    /// The season whose wallpaper was last applied automatically.
    public var appliedSeason: Season?
    /// When the seasonal check last ran, so it runs at most once a day.
    public var lastCheck: Date?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case favourites, changeWithSeasons, scaling, appliedSeason, lastCheck
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A favourite that no longer decodes is dropped instead of losing the whole list.
        favourites = c(.favourites, [Lenient<Favourite>]()).compactMap(\.value)
        changeWithSeasons = c(.changeWithSeasons, false)
        scaling = c(.scaling, .fill)
        appliedSeason = c(.appliedSeason, nil)
        lastCheck = c(.lastCheck, nil)
    }

    public func isFavourite(_ id: String) -> Bool { favourites.contains { $0.wallpaper.id == id } }

    public mutating func toggleFavourite(_ wallpaper: Wallpaper, season: Season?) {
        if let i = favourites.firstIndex(where: { $0.wallpaper.id == wallpaper.id }) {
            favourites.remove(at: i)
        } else {
            favourites.insert(Favourite(wallpaper: wallpaper, season: season), at: 0)
        }
    }

    /// Reads a library, falling back to an empty one when the file is missing or damaged.
    public static func decode(_ data: Data) -> WallpaperLibrary {
        (try? JSONDecoder.harbor.decode(WallpaperLibrary.self, from: data)) ?? WallpaperLibrary()
    }

    public func encoded() throws -> Data { try JSONEncoder.harbor.encode(self) }

    private struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}

/// How a wallpaper is fitted to the screen.
public enum WallpaperScaling: String, Codable, CaseIterable, Sendable {
    case fill, fit, stretch, center

    public var title: String {
        switch self {
        case .fill: "Fill Screen"
        case .fit: "Fit to Screen"
        case .stretch: "Stretch to Fill"
        case .center: "Centre"
        }
    }
}

/// Decides when "Change with the seasons" should act.
public enum SeasonalChange {
    /// The season to switch to, or nil when nothing should happen: the feature is off,
    /// it already checked today, or the season's wallpaper is already applied.
    public static func due(_ library: WallpaperLibrary, now: Date, calendar: Calendar = .current) -> Season? {
        guard library.changeWithSeasons else { return nil }
        if let last = library.lastCheck, calendar.isDate(last, inSameDayAs: now) { return nil }
        let season = Season.of(now, calendar: calendar)
        return season == library.appliedSeason ? nil : season
    }

    /// A favourite saved from this season's collection, picked with `roll` in 0..<1.
    public static func favourite(for season: Season, in library: WallpaperLibrary, roll: Double) -> Wallpaper? {
        let picks = library.favourites.filter { $0.season == season }.map(\.wallpaper)
        guard !picks.isEmpty else { return nil }
        return picks[min(Int(roll * Double(picks.count)), picks.count - 1)]
    }
}
