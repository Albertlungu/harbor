import AppKit
import HarborCore
import SwiftUI

/// Search and browse Wallhaven, with seasonal collections and favourites.
struct WallpaperBrowserView: View {
    @State private var browser = WallpaperBrowser()

    var body: some View {
        @Bindable var browser = browser
        NavigationSplitView {
            List(selection: Binding(get: { browser.collection }, set: { if let c = $0 { select(c) } })) {
                Section("Browse") {
                    Label("4K Library", systemImage: "photo.on.rectangle.angled").tag(WallpaperCollection.library)
                    Label("Favourites", systemImage: "heart").tag(WallpaperCollection.favourites)
                }
                Section("Seasons") {
                    Label("This WallpaperSeason (\(WallpaperSeason.of(Date()).title))", systemImage: "calendar")
                        .tag(WallpaperCollection.currentSeason)
                    ForEach(WallpaperSeason.allCases, id: \.self) { season in
                        Label(season.title, systemImage: season.symbol).tag(WallpaperCollection.season(season))
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(spacing: 0) {
                FilterBar(browser: browser)
                Divider()
                ResultsGrid(browser: browser)
            }
            .inspector(isPresented: Binding(get: { browser.selection != nil }, set: { if !$0 { browser.selection = nil } })) {
                if let wallpaper = browser.selection {
                    WallpaperDetail(browser: browser, wallpaper: wallpaper)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
            }
            .navigationTitle(title)
        }
        .searchable(text: Binding(get: { browser.text }, set: { v in
            browser.text = v
            // Typing searches the whole library, whichever collection was showing.
            if !v.isEmpty, browser.collection != .library { browser.collection = .library }
        }), placement: .toolbar, prompt: "Search wallpapers")
        .task(id: browser.request) { await browser.load(browser.request) }
        .onDisappear { browser.stop() }
    }

    private var title: String {
        switch browser.collection {
        case .library: "Wallpapers"
        case .favourites: "Favourites"
        case .currentSeason, .season: "\(browser.season?.title ?? "") Wallpapers"
        }
    }

    private func select(_ collection: WallpaperCollection) {
        browser.collection = collection
        browser.theme = nil
        browser.selection = nil
    }
}

private struct FilterBar: View {
    @Bindable var browser: WallpaperBrowser
    @State private var choosingColor = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.l) {
                Picker("Size", selection: $browser.minimum) {
                    ForEach(WallpaperMinimum.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Toggle("Match my screens", isOn: $browser.matchScreens)
                    .help("Only show pictures shaped like your displays")
                Button { choosingColor = true } label: {
                    HStack(spacing: Tokens.Space.xs) {
                        Swatch(hex: browser.color)
                        Text(browser.color == nil ? "Any Colour" : "Colour")
                    }
                }
                .popover(isPresented: $choosingColor) { ColorGrid(selection: $browser.color, done: { choosingColor = false }) }
                Picker("Sort", selection: $browser.sorting) {
                    ForEach(WallpaperSorting.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            .controlSize(.small)
            if let season = browser.season {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Space.s) {
                        ForEach(season.themes, id: \.self) { theme in
                            let on = (browser.theme ?? season.themes[0]) == theme
                            Button(theme.capitalized) { browser.theme = theme }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(on ? .accentColor : nil)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .disabled(browser.collection == .favourites)
    }
}

private struct ColorGrid: View {
    @Binding var selection: String?
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: Tokens.Space.s), count: 10), spacing: Tokens.Space.s) {
                ForEach(WallpaperPalette.colors, id: \.self) { hex in
                    Button { selection = hex; done() } label: {
                        Swatch(hex: hex, size: 22).overlay {
                            if selection == hex { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white).shadow(radius: 1) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Any Colour") { selection = nil; done() }.controlSize(.small)
        }
        .padding(Tokens.Space.l)
    }
}

private struct Swatch: View {
    let hex: String?
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(hex.flatMap { UInt32($0, radix: 16) }.map { Color(nsColor: NSColor(hex: $0)) }
                  .map(AnyShapeStyle.init) ?? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)))
            .overlay(Circle().strokeBorder(Tokens.border))
            .frame(width: size, height: size)
    }
}

private struct ResultsGrid: View {
    @Bindable var browser: WallpaperBrowser

    var body: some View {
        if let error = browser.error {
            ContentUnavailableView("Couldn't Load Wallpapers", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if browser.items.isEmpty && !browser.loading {
            if browser.collection == .favourites {
                ContentUnavailableView("No Favourites Yet", systemImage: "heart",
                                       description: Text("Select a wallpaper and press the heart to keep it here."))
            } else {
                ContentUnavailableView.search(text: browser.request?.text ?? "")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: Tokens.Space.l)],
                          spacing: Tokens.Space.l) {
                    ForEach(browser.items) { wallpaper in
                        Tile(wallpaper: wallpaper, selected: browser.selection?.id == wallpaper.id,
                             favourite: WallpaperStore.shared.library.isFavourite(wallpaper.id))
                            .onTapGesture { browser.selection = wallpaper }
                            .onAppear { browser.loadMore(after: wallpaper) }
                    }
                }
                .padding(Tokens.Space.xl)
            }
            .overlay {
                if browser.loading { ProgressView().controlSize(.large) }
            }
        }
    }
}

private struct Tile: View {
    let wallpaper: Wallpaper
    let selected: Bool
    let favourite: Bool
    @State private var image: NSImage?

    var body: some View {
        Color(nsColor: .quaternaryLabelColor)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: Tokens.Space.xs) {
                    Text(wallpaper.resolution)
                    if favourite { Image(systemName: "heart.fill") }
                }
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, Tokens.Space.s)
                .padding(.vertical, Tokens.Space.xxs)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(Tokens.Space.s)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.card)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .contentShape(Rectangle())
            // Runs only while the tile is on screen; scrolling away cancels the fetch.
            .task(id: wallpaper.thumb) {
                image = WallpaperService.memory.image(for: wallpaper.thumb)
                if image == nil {
                    let loaded = await WallpaperService.thumbnail(wallpaper.thumb, maxPixels: 520)
                    withAnimation(.easeOut(duration: Tokens.Motion.reveal)) { image = loaded }
                }
            }
    }
}

private struct WallpaperDetail: View {
    @Bindable var browser: WallpaperBrowser
    let wallpaper: Wallpaper
    @State private var image: NSImage?

    var body: some View {
        let store = WallpaperStore.shared
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                Color(nsColor: .quaternaryLabelColor)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
                    .task(id: wallpaper.thumb) { image = await WallpaperService.thumbnail(wallpaper.thumb, maxPixels: 520) }

                HStack {
                    VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
                        Text(wallpaper.resolution).font(.headline.monospacedDigit())
                        if wallpaper.fileSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(wallpaper.fileSize), countStyle: .file))
                                .font(.caption).foregroundStyle(Tokens.textMuted)
                        }
                    }
                    Spacer()
                    let favourite = store.library.isFavourite(wallpaper.id)
                    Button { browser.toggleFavourite(wallpaper) } label: {
                        Image(systemName: favourite ? "heart.fill" : "heart")
                    }
                    .help(favourite ? "Remove from Favourites" : "Add to Favourites")
                }
                if !wallpaper.colors.isEmpty {
                    HStack(spacing: Tokens.Space.xs) {
                        ForEach(wallpaper.colors, id: \.self) { Swatch(hex: String($0.dropFirst()), size: 16) }
                    }
                }

                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Button { Task { await browser.set(wallpaper, on: NSScreen.screens) } } label: {
                        Label("Set as Wallpaper", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    if NSScreen.screens.count > 1 {
                        Menu("Set on One Screen") {
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                Button(screen.localizedName) { Task { await browser.set(wallpaper, on: [screen]) } }
                            }
                        }
                    }
                    Button { Task { await browser.download(wallpaper) } } label: {
                        Label("Download", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                    }
                    Picker("Scaling", selection: Binding(get: { store.library.scaling },
                                                         set: { v in store.update { $0.scaling = v } })) {
                        ForEach(WallpaperScaling.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                .disabled(browser.working)
                .controlSize(.large)

                if browser.working {
                    HStack { ProgressView().controlSize(.small); Text("Downloading the full picture…").font(.caption) }
                } else if let status = browser.status {
                    Text(status).font(.caption).foregroundStyle(Tokens.textMuted)
                }

                Divider()
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Link("View on Wallhaven", destination: wallpaper.page)
                    if let source = URL(string: wallpaper.source), source.scheme?.hasPrefix("http") == true {
                        Link("Original source", destination: source)
                    }
                    Text("Pictures come from Wallhaven and belong to their creators. Use them as your own wallpaper; ask the creator before using them anywhere else.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Tokens.Space.xl)
        }
        .onChange(of: wallpaper.id) { browser.status = nil }
    }
}

extension WallpaperSeason {
    var symbol: String {
        switch self {
        case .winter: "snowflake"
        case .spring: "leaf"
        case .summer: "sun.max"
        case .autumn: "wind"
        }
    }
}
