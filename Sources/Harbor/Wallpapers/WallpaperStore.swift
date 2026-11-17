import AppKit
import HarborCore
import Observation

/// Favourites and wallpaper preferences, saved to wallpapers.json in Harbor's config folder.
/// Kept apart from config.json so the wallpaper browser never rewrites the dock config.
@MainActor
@Observable
final class WallpaperStore {
    static let shared = WallpaperStore(directory: AppModel.configDirectory)

    private(set) var library: WallpaperLibrary
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(directory: URL) {
        url = directory.appendingPathComponent("wallpapers.json")
        library = (try? Data(contentsOf: url)).map(WallpaperLibrary.decode) ?? WallpaperLibrary()
    }

    func update(_ change: (inout WallpaperLibrary) -> Void) {
        var copy = library
        change(&copy)
        guard copy != library else { return }
        library = copy
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copy.encoded().write(to: url, options: .atomic)
        } catch {
            NSLog("Harbor: couldn't save wallpapers.json: \(error.localizedDescription)")
        }
    }

    // MARK: Change with the seasons

    /// Checks once now and again after each wake. No timer: a Mac that stays awake across
    /// a season boundary changes at its next wake or launch.
    func startSeasonalChanges() {
        checkSeason()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WallpaperStore.shared.checkSeason() }
        }
    }

    func checkSeason() {
        let now = Date()
        guard let season = SeasonalChange.due(library, now: now) else { return }
        update { $0.lastCheck = now }
        Task { await applySeason(season) }
    }

    /// Puts a wallpaper for `season` on every screen: a favourite saved from that season,
    /// otherwise one of the season's top-rated pictures.
    func applySeason(_ season: WallpaperSeason) async {
        do {
            var pick = SeasonalChange.favourite(for: season, in: library, roll: Double.random(in: 0..<1))
            if pick == nil {
                let query = WallpaperQuery(text: season.themes[0], ratios: WallpaperRatio.matching(screens: WallpaperService.screenSizes),
                                           sorting: .top, categories: "100")
                pick = try await WallpaperService.search(query).items.prefix(12).randomElement()
            }
            guard let pick else { return }
            let file = try await WallpaperService.download(pick)
            try WallpaperService.apply(file, to: NSScreen.screens, scaling: library.scaling)
            update { $0.appliedSeason = season }
        } catch {
            // Left unapplied, so tomorrow's check tries again.
            NSLog("Harbor: seasonal wallpaper failed: \(error.localizedDescription)")
        }
    }
}
