import AppKit
import HarborCore
import Observation

/// State for the wallpaper browser window. Lives only while the window is open.
@MainActor
@Observable
final class WallpaperBrowser {
    var collection: WallpaperCollection = .library
    var text = ""
    /// The chosen theme within a season collection; nil means the season's first theme.
    var theme: String?
    var minimum: WallpaperMinimum = .uhd4k
    var matchScreens = true
    var color: String?
    var sorting: WallpaperSorting = .relevance

    private(set) var items: [Wallpaper] = []
    private(set) var total = 0
    private(set) var loading = false
    private(set) var error: String?
    var selection: Wallpaper?
    /// A short result line for Set and Download, such as "Saved to Pictures".
    var status: String?
    private(set) var working = false

    @ObservationIgnored private var nextPage: WallpaperQuery?
    @ObservationIgnored private var moreTask: Task<Void, Never>?

    init() {
        if let search = ProcessInfo.processInfo.environment["HARBOR_WALLPAPERS"], search != "1" { text = search }
    }

    var season: WallpaperSeason? { collection.season(on: Date()) }

    /// The first page's request, or nil for favourites, which need no network.
    var request: WallpaperQuery? {
        let ratios = matchScreens ? WallpaperRatio.matching(screens: WallpaperService.screenSizes) : []
        if let season {
            return WallpaperQuery(text: theme ?? season.themes[0], minimum: minimum, ratios: ratios, color: color,
                                  sorting: sorting, categories: "100")
        }
        if collection == .favourites { return nil }
        return WallpaperQuery(text: text, minimum: minimum, ratios: ratios, color: color, sorting: sorting)
    }

    /// Loads the first page of `request`. Run from `.task(id:)`, so a newer request
    /// cancels this one, and the pause doubles as the search field's debounce.
    func load(_ request: WallpaperQuery?) async {
        moreTask?.cancel()
        guard let request else {
            items = WallpaperStore.shared.library.favourites.map(\.wallpaper)
            total = items.count
            loading = false
            error = nil
            nextPage = nil
            return
        }
        loading = true
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let page = try await WallpaperService.search(request)
            guard !Task.isCancelled else { return }
            items = page.items
            total = page.total
            error = nil
            nextPage = page.hasMore ? request.next(page) : nil
        } catch {
            guard !Task.isCancelled else { return }
            items = []
            total = 0
            self.error = error.localizedDescription
            nextPage = nil
        }
        loading = false
    }

    /// Fetches the next page when the grid nears its end.
    func loadMore(after item: Wallpaper) {
        guard let next = nextPage, moreTask == nil, items.suffix(8).contains(where: { $0.id == item.id }) else { return }
        moreTask = Task {
            defer { moreTask = nil }
            guard let page = try? await WallpaperService.search(next), !Task.isCancelled else { return }
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            nextPage = page.hasMore ? next.next(page) : nil
        }
    }

    func stop() {
        moreTask?.cancel()
        WallpaperService.memory.removeAll()
        Task.detached(priority: .background) { WallpaperService.trimCache() }
    }

    // MARK: Actions

    func toggleFavourite(_ wallpaper: Wallpaper) {
        WallpaperStore.shared.update { $0.toggleFavourite(wallpaper, season: season) }
        if collection == .favourites {
            items = WallpaperStore.shared.library.favourites.map(\.wallpaper)
        }
    }

    func set(_ wallpaper: Wallpaper, on screens: [NSScreen]) async {
        await perform {
            let file = try await WallpaperService.download(wallpaper)
            try WallpaperService.apply(file, to: screens, scaling: WallpaperStore.shared.library.scaling)
            return screens.count == 1 ? "Set on \(screens[0].localizedName)." : "Set on all screens."
        }
    }

    func download(_ wallpaper: Wallpaper) async {
        await perform {
            let file = try await WallpaperService.download(wallpaper)
            NSWorkspace.shared.activateFileViewerSelecting([file])
            return "Saved to Pictures › Harbor Wallpapers."
        }
    }

    private func perform(_ work: () async throws -> String) async {
        working = true
        status = nil
        defer { working = false }
        do { status = try await work() } catch { status = error.localizedDescription }
    }
}

private extension WallpaperQuery {
    func next(_ page: WallpaperPage) -> WallpaperQuery {
        var next = self
        next.page = page.page + 1
        next.seed = page.seed ?? seed
        return next
    }
}
