import AppKit
import HarborCore
import SwiftUI

/// The Wallpapers page in Settings: opens the browser and holds the seasonal option.
struct WallpaperSettings: View {
    var body: some View {
        let store = WallpaperStore.shared
        let season = WallpaperSeason.of(Date())
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                        Text("Search 4K wallpapers and seasonal collections.")
                        Text("\(store.library.favourites.count) favourites").font(.caption).foregroundStyle(Tokens.textMuted)
                    }
                    Spacer()
                    Button("Open Wallpapers…") { WallpaperWindow.shared.show() }
                }
            }
            Section("Seasons") {
                Toggle("Change with the seasons", isOn: Binding(
                    get: { store.library.changeWithSeasons },
                    set: { on in
                        store.update {
                            $0.changeWithSeasons = on
                            // Turning it on applies this season's pick now rather than waiting for the next one.
                            $0.appliedSeason = nil
                            $0.lastCheck = nil
                        }
                        if on { store.checkSeason() }
                    }))
                Text("It's \(season.title.lowercased()). Harbor picks a \(season.title.lowercased()) favourite, or one of the season's top pictures, and checks again once a day at launch and when your Mac wakes.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Picker("Scaling", selection: Binding(get: { store.library.scaling }, set: { v in store.update { $0.scaling = v } })) {
                    ForEach(WallpaperScaling.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Downloads") {
                LabeledContent("Folder", value: "Pictures › Harbor Wallpapers")
                Button("Show in Finder") {
                    let folder = WallpaperService.downloadDirectory
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
            }
            Section("Source") {
                Text("Pictures come from Wallhaven, safe-for-work results only. They belong to their creators: use them as your own wallpaper, and check with the creator before using them anywhere else.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Link("wallhaven.cc", destination: URL(string: "https://wallhaven.cc")!)
            }
        }
    }
}
