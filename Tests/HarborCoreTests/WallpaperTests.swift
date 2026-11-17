import Foundation
import Testing
@testable import HarborCore

@Suite struct WallpaperTests {
    // Trimmed from a live `search?q=winter snow` response; the third entry lacks a path.
    private let sample = """
    {"data":[{"id":"p8zy3m","url":"https://wallhaven.cc/w/p8zy3m","short_url":"https://whvn.cc/p8zy3m","views":3869,"favorites":3,"source":"","purity":"sfw","category":"general","dimension_x":3888,"dimension_y":2592,"resolution":"3888x2592","ratio":"1.5","file_size":738532,"file_type":"image/jpeg","created_at":"2020-04-05 10:52:18","colors":["#999999","#abbcda","#000000","#424153","#663399"],"path":"https://w.wallhaven.cc/full/p8/wallhaven-p8zy3m.jpg","thumbs":{"large":"https://th.wallhaven.cc/lg/p8/p8zy3m.jpg","original":"https://th.wallhaven.cc/orig/p8/p8zy3m.jpg","small":"https://th.wallhaven.cc/small/p8/p8zy3m.jpg"}},
    {"id":"v9v525","url":"https://wallhaven.cc/w/v9v525","short_url":"https://whvn.cc/v9v525","views":4966,"favorites":34,"source":"","purity":"sfw","category":"general","dimension_x":3840,"dimension_y":2160,"resolution":"3840x2160","ratio":"1.78","file_size":3888159,"file_type":"image/jpeg","created_at":"2022-02-12 04:47:09","colors":["#999999"],"path":"https://w.wallhaven.cc/full/v9/wallhaven-v9v525.jpg","thumbs":{"large":"https://th.wallhaven.cc/lg/v9/v9v525.jpg","original":"https://th.wallhaven.cc/orig/v9/v9v525.jpg","small":"https://th.wallhaven.cc/small/v9/v9v525.jpg"}},
    {"id":"broken","url":"https://wallhaven.cc/w/broken","thumbs":{}}],
    "meta":{"current_page":1,"last_page":47,"per_page":24,"total":1111,"query":"winter snow","seed":null}}
    """

    private func items(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Decoding

    @Test func decodesSearchPage() throws {
        let page = try WallpaperPage.decode(Data(sample.utf8))
        #expect(page.items.map(\.id) == ["p8zy3m", "v9v525"])
        #expect(page.page == 1 && page.lastPage == 47 && page.total == 1111 && page.hasMore)
        #expect(page.seed == nil)
        let first = page.items[0]
        #expect(first.width == 3888 && first.height == 2592)
        #expect(first.thumb.absoluteString == "https://th.wallhaven.cc/lg/p8/p8zy3m.jpg")
        #expect(first.page.absoluteString == "https://wallhaven.cc/w/p8zy3m")
        #expect(first.fileName == "wallhaven-p8zy3m.jpg")
    }

    @Test func rejectsNonJSON() {
        #expect(throws: (any Error).self) { try WallpaperPage.decode(Data("<html>".utf8)) }
    }

    // MARK: Query building

    @Test func searchIsAlwaysSafeForWork() {
        let q = items(WallpaperQuery(text: "  mountains ").url)
        #expect(q["purity"] == "100")
        #expect(q["q"] == "mountains")
        #expect(q["atleast"] == "3840x2160")
        #expect(q["sorting"] == "relevance")
        #expect(q["categories"] == "110")
        #expect(q["page"] == nil)
    }

    @Test func emptyRelevanceSearchUsesTopList() {
        let q = items(WallpaperQuery().url)
        #expect(q["q"] == nil)
        #expect(q["sorting"] == "toplist")
        #expect(q["topRange"] == "1y")
    }

    @Test func filtersAndPaging() {
        var query = WallpaperQuery(text: "sea", minimum: .any, ratios: [.r16x9, .r16x10], color: "0066cc", sorting: .random)
        query.page = 3
        query.seed = "abc123"
        let q = items(query.url)
        #expect(q["atleast"] == nil)
        #expect(q["ratios"] == "16x9,16x10")
        #expect(q["colors"] == "0066cc")
        #expect(q["sorting"] == "random")
        #expect(q["page"] == "3")
        #expect(q["seed"] == "abc123")
    }

    @Test func seedOnlyForRandom() {
        var query = WallpaperQuery(text: "sea", sorting: .latest)
        query.seed = "abc123"
        #expect(items(query.url)["seed"] == nil)
        #expect(items(query.url)["sorting"] == "date_added")
    }

    // MARK: Ratios

    @Test func nearestRatioForCommonScreens() {
        #expect(WallpaperRatio.nearest(width: 3840, height: 2160) == .r16x9)
        #expect(WallpaperRatio.nearest(width: 2880, height: 1800) == .r16x10)
        #expect(WallpaperRatio.nearest(width: 3440, height: 1440) == .r21x9)
        #expect(WallpaperRatio.nearest(width: 3024, height: 1964) == .r3x2)
        // A portrait monitor matches by its long side.
        #expect(WallpaperRatio.nearest(width: 1440, height: 2560) == .r16x9)
        #expect(WallpaperRatio.matching(screens: [CGSize(width: 2560, height: 1440), CGSize(width: 2880, height: 1800),
                                                  CGSize(width: 1920, height: 1080)]) == [.r16x9, .r16x10])
    }

    // MARK: Seasons

    @Test func seasonsByMonth() {
        #expect([12, 1, 2].map(WallpaperSeason.of(month:)) == [.winter, .winter, .winter])
        #expect([3, 5].map(WallpaperSeason.of(month:)) == [.spring, .spring])
        #expect([6, 8].map(WallpaperSeason.of(month:)) == [.summer, .summer])
        #expect([9, 11].map(WallpaperSeason.of(month:)) == [.autumn, .autumn])
        for season in WallpaperSeason.allCases { #expect(!season.themes.isEmpty) }
    }

    @Test func collectionResolvesCurrentSeason() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17))!
        #expect(WallpaperCollection.currentSeason.season(on: november, calendar: calendar) == .autumn)
        #expect(WallpaperCollection.season(.spring).season(on: november, calendar: calendar) == .spring)
        #expect(WallpaperCollection.library.season(on: november, calendar: calendar) == nil)
    }

    @Test func seasonalChangeRunsOncePerDayAndSeason() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 9))!
        var library = WallpaperLibrary()
        #expect(SeasonalChange.due(library, now: day, calendar: calendar) == nil)
        library.changeWithSeasons = true
        #expect(SeasonalChange.due(library, now: day, calendar: calendar) == .winter)
        library.lastCheck = day.addingTimeInterval(-3600)
        #expect(SeasonalChange.due(library, now: day, calendar: calendar) == nil)
        library.lastCheck = day.addingTimeInterval(-86_400)
        library.appliedSeason = .winter
        #expect(SeasonalChange.due(library, now: day, calendar: calendar) == nil)
        library.appliedSeason = .autumn
        #expect(SeasonalChange.due(library, now: day, calendar: calendar) == .winter)
    }

    @Test func seasonalFavouritePick() throws {
        let page = try WallpaperPage.decode(Data(sample.utf8))
        var library = WallpaperLibrary()
        #expect(SeasonalChange.favourite(for: .winter, in: library, roll: 0.5) == nil)
        library.toggleFavourite(page.items[0], season: .winter)
        library.toggleFavourite(page.items[1], season: nil)
        #expect(SeasonalChange.favourite(for: .winter, in: library, roll: 0.99)?.id == "p8zy3m")
        #expect(SeasonalChange.favourite(for: .summer, in: library, roll: 0) == nil)
        library.toggleFavourite(page.items[0], season: nil)
        #expect(!library.isFavourite("p8zy3m") && library.isFavourite("v9v525"))
    }

    // MARK: Library file

    @Test func libraryRoundTripsAndDecodesLeniently() throws {
        let page = try WallpaperPage.decode(Data(sample.utf8))
        var library = WallpaperLibrary()
        library.toggleFavourite(page.items[0], season: .autumn)
        library.changeWithSeasons = true
        library.scaling = .fit
        #expect(WallpaperLibrary.decode(try library.encoded()) == library)

        let damaged = """
        {"favourites":[{"wallpaper":{"id":"x"}},{"wallpaper":{"id":"ok","page":"https://wallhaven.cc/w/ok",
        "full":"https://w.wallhaven.cc/full/ok/a.jpg","thumb":"https://th.wallhaven.cc/lg/ok/ok.jpg"},"season":"summer"}],
        "scaling":"sideways"}
        """
        let decoded = WallpaperLibrary.decode(Data(damaged.utf8))
        #expect(decoded.favourites.map(\.wallpaper.id) == ["ok"])
        #expect(decoded.favourites.first?.season == .summer)
        #expect(decoded.scaling == .fill)
        #expect(WallpaperLibrary.decode(Data("nonsense".utf8)) == WallpaperLibrary())
    }

    // MARK: Cache

    @Test func cacheKeysAreFlatAndStable() {
        let url = URL(string: "https://th.wallhaven.cc/lg/p8/p8zy3m.jpg")!
        #expect(WallpaperCacheKey.fileName(for: url) == "lg-p8-p8zy3m.jpg")
        #expect(WallpaperCacheKey.fileName(for: URL(string: "https://th.wallhaven.cc/small/p8/p8zy3m.jpg")!) == "small-p8-p8zy3m.jpg")
        #expect(WallpaperCacheKey.fileName(for: URL(string: "https://x.test/a b/c?.jpg")!) == "a_b-c")
    }

    @Test func cacheTrimDropsOldestFirst() {
        let now = Date()
        let files = [
            CachedFile(name: "new", size: 40, lastUsed: now),
            CachedFile(name: "old", size: 40, lastUsed: now.addingTimeInterval(-100)),
            CachedFile(name: "mid", size: 40, lastUsed: now.addingTimeInterval(-50)),
        ]
        #expect(WallpaperCacheTrim.evictions(files, limit: 200).isEmpty)
        #expect(WallpaperCacheTrim.evictions(files, limit: 100) == ["old"])
        #expect(WallpaperCacheTrim.evictions(files, limit: 40) == ["old", "mid"])
    }
}
