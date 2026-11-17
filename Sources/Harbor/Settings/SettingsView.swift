import AppKit
import HarborCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case personality, general, behavior, newDocks, icons, wallpapers, previews, permissions, backup, integrations, diagnostics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .personality: "Personality"
        case .general: "General"
        case .behavior: "Behavior"
        case .newDocks: "New Docks"
        case .icons: "Icon Library"
        case .wallpapers: "Wallpapers"
        case .previews: "Window Previews"
        case .permissions: "Permissions"
        case .backup: "Backup"
        case .integrations: "Integrations"
        case .diagnostics: "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .personality: "sparkles"
        case .general: "gearshape"
        case .behavior: "cursorarrow.click"
        case .newDocks: "plus.rectangle.on.rectangle"
        case .icons: "photo.on.rectangle"
        case .wallpapers: "photo.artframe"
        case .previews: "rectangle.on.rectangle"
        case .permissions: "lock.shield"
        case .backup: "externaldrive"
        case .integrations: "puzzlepiece.extension"
        case .diagnostics: "stethoscope"
        }
    }

    var group: String {
        switch self {
        case .personality, .general, .behavior: "App"
        case .newDocks, .icons, .wallpapers: "Personalize"
        case .previews: "Features"
        case .permissions, .backup, .integrations: "System"
        case .diagnostics: "Support"
        }
    }
}

/// App-wide settings. Per-dock settings live only in the Manager.
struct SettingsView: View {
    // HARBOR_SETTINGS opens a given page, a development aid for screenshots.
    @State private var page: SettingsPage = ProcessInfo.processInfo.environment["HARBOR_SETTINGS"]
        .flatMap(SettingsPage.init(rawValue:)) ?? .general

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(["App", "Personalize", "Features", "System", "Support"], id: \.self) { group in
                    Section(group) {
                        ForEach(SettingsPage.allCases.filter { $0.group == group }) { p in
                            Label(p.title, systemImage: p.symbol).tag(p)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            FillAvailable {
                switch page {
                case .personality: PersonalitySettings()
                case .general: GeneralSettings()
                case .behavior: BehaviorSettings()
                case .newDocks: NewDockSettings()
                case .icons: IconLibrarySettings()
                case .wallpapers: WallpaperSettings()
                case .previews: PreviewSettingsPage()
                case .permissions: PermissionsSettings()
                case .backup: BackupSettings()
                case .integrations: IntegrationsSettings()
                case .diagnostics: DiagnosticsSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(page.title)
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var loginError: String?
    @State private var dockError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.store.settings.launchAtLogin },
                    set: { loginError = model.setLaunchAtLogin($0) }))
                if model.launchAtLoginNeedsApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.").font(.caption)
                        Button("Open Login Items") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        }
                    }
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(Tokens.danger) }
                Toggle("Open the Manager at launch", isOn: model.setting(\.showManagerOnLaunch))
                Picker("Show Harbor in", selection: Binding(
                    get: { model.store.settings.presentation },
                    set: { v in
                        model.store.updateSettings { $0.presentation = v }
                        model.applyPresentation()
                    })) {
                    Text("The menu bar").tag(Presentation.menuBar)
                    Text("The Dock").tag(Presentation.dockApp)
                    Text("Both").tag(Presentation.both)
                }
            }

            Section("macOS Dock") {
                Toggle("Replace the macOS Dock", isOn: Binding(
                    get: { model.store.settings.deepHideNativeDock },
                    set: { dockError = model.setReplaceNativeDock($0) }))
                Text("Hides the macOS Dock while Harbor is open and brings it back when you quit. If you have no dock yet, Harbor makes one from your current Dock.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                if let dockError {
                    HStack {
                        Text(dockError).font(.caption).foregroundStyle(Tokens.danger)
                        Button("Try Again") { self.dockError = model.setReplaceNativeDock(model.store.settings.deepHideNativeDock) }
                    }
                }
                Text("macOS still shows its own Dock in Mission Control. Moving it to an edge you don't use keeps it out of the way there.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Button("Open Desktop & Dock Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                }
            }

            Section("Appearance") {
                Toggle("Always use opaque backgrounds", isOn: model.setting(\.opaqueBackgrounds))
                if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    Text("Reduce Transparency is on in macOS, so docks are opaque anyway.")
                        .font(.caption).foregroundStyle(Tokens.textMuted)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Link("Release notes and updates", destination: URL(string: "https://github.com/Albertlungu/harbor/releases")!)
            }
        }
    }
}

private struct BehaviorSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Folders") {
                Picker("Clicking a folder", selection: model.setting(\.folderClick)) {
                    Text("Browses it beside the dock").tag(FolderClick.browse)
                    Text("Opens it in Finder").tag(FolderClick.openInFinder)
                }
                LabeledContent("Open folders with") {
                    HStack {
                        Text(model.store.settings.folderApp.map { FileManager.default.displayName(atPath: $0) } ?? "Finder")
                        Button("Choose…") { if let p = AppPicker.pick() { model.store.updateSettings { $0.folderApp = p } } }
                        if model.store.settings.folderApp != nil {
                            Button("Use Finder") { model.store.updateSettings { $0.folderApp = nil } }
                        }
                    }
                }
                Toggle("Offer Move to Trash in stacks and folders", isOn: model.setting(\.showMoveToTrash))
            }
            Section("Dragging") {
                Toggle("Snap floating docks to edges and the center", isOn: model.setting(\.magneticSnapping))
            }
            Section("Window space") {
                Toggle("Keep windows from covering pinned docks", isOn: model.setting(\.reserveDockSpace))
                Toggle("Also after I move or resize a window", isOn: model.setting(\.reserveOnDrag))
                    .disabled(!model.store.settings.reserveDockSpace)
                if !WindowControl.isTrusted {
                    Button("Allow Accessibility Access") { WindowControl.requestTrust() }
                }
            }
            Section("Running apps") {
                Toggle("Show a dot under open apps", isOn: model.setting(\.showRunningIndicators))
                ColorPicker("Dot color", selection: Binding(
                    get: { (model.store.settings.indicatorColor ?? RGBA(0.24, 0.24, 0.26)).color },
                    set: { c in model.store.updateSettings { $0.indicatorColor = RGBA(c) } }))
                if model.store.settings.indicatorColor != nil {
                    Button("Use Default Color") { model.store.updateSettings { $0.indicatorColor = nil } }
                }
                Picker("When an app launches", selection: model.setting(\.attentionStyle)) {
                    Text("Bounce").tag(AttentionStyle.bounce)
                    Text("Flash once").tag(AttentionStyle.flashOnce)
                    Text("Badge only").tag(AttentionStyle.badgeOnly)
                    Text("Nothing").tag(AttentionStyle.off)
                }
                LabeledContent("Never show in app lists") {
                    VStack(alignment: .trailing) {
                        ForEach(model.store.settings.excludedApps, id: \.self) { path in
                            HStack {
                                Text(FileManager.default.displayName(atPath: path))
                                Button { model.store.updateSettings { $0.excludedApps.removeAll { $0 == path } } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("Add App…") { if let p = AppPicker.pick() { model.store.updateSettings { $0.excludedApps.append(p) } } }
                    }
                }
            }
            Section("Gestures") {
                Toggle("Modifier clicks", isOn: model.setting(\.clickGestures))
                if model.store.settings.clickGestures {
                    ForEach(ClickModifier.allCases, id: \.self) { mod in
                        Picker(label(mod), selection: Binding(
                            get: { model.store.settings.clickGestureActions[mod] ?? .nothing },
                            set: { v in model.store.updateSettings { $0.clickGestureActions[mod] = v } })) {
                            ForEach(GestureAction.allCases, id: \.self) { Text(actionTitle($0)).tag($0) }
                        }
                    }
                }
                Text("Control-click always opens the menu.").font(.caption).foregroundStyle(Tokens.textMuted)
            }
            Section("Privacy") {
                Toggle("Hide docks from screen sharing and recordings", isOn: model.setting(\.hideFromScreenSharing))
            }
        }
    }

    private func label(_ m: ClickModifier) -> String {
        switch m {
        case .command: "⌘-click"
        case .option: "⌥-click"
        case .optionCommand: "⌥⌘-click"
        case .shift: "⇧-click"
        case .middle: "Middle click"
        }
    }

    private func actionTitle(_ a: GestureAction) -> String {
        switch a {
        case .nothing: "Nothing"
        case .revealInFinder: "Show in Finder"
        case .toggleHidden: "Hide or show the app"
        case .showOnlyThis: "Show only this app"
        case .quit: "Quit the app"
        case .minimizeFront: "Minimize its front window"
        }
    }
}

private struct NewDockSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Use my own look for new docks", isOn: model.setting(\.newDocks.customizeStyle))
                if model.store.settings.newDocks.customizeStyle {
                    PresetPicker(title: "Icon size", preset: model.setting(\.newDocks.style.iconSizePreset), custom: .custom,
                                 value: model.setting(\.newDocks.style.customIconSize), range: 20...128, unit: "pt")
                    PresetPicker(title: "Bar thickness", preset: model.setting(\.newDocks.style.thicknessPreset), custom: .custom,
                                 value: model.setting(\.newDocks.style.customThickness), range: 24...200, unit: "pt")
                    Picker("Space between icons", selection: model.setting(\.newDocks.style.spacing)) {
                        ForEach(SpacingPreset.allCases, id: \.self) { Text($0 == .normal ? "Default" : $0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Magnify on hover", isOn: model.setting(\.newDocks.style.magnify))
                }
            }
            Section {
                Toggle("Use my own behavior for new docks", isOn: model.setting(\.newDocks.customizeBehavior))
                if model.store.settings.newDocks.customizeBehavior {
                    Toggle("Hide automatically", isOn: model.setting(\.newDocks.behavior.autoHide))
                    Toggle("Hide when an app is fullscreen", isOn: model.setting(\.newDocks.behavior.hideInFullscreen))
                    Picker("Clicking the frontmost app", selection: model.setting(\.newDocks.behavior.activeAppClick)) {
                        Text("Does nothing").tag(ActiveAppClick.none)
                        Text("Minimizes its window").tag(ActiveAppClick.minimize)
                        Text("Hides it").tag(ActiveAppClick.hide)
                        Text("Shows its next window").tag(ActiveAppClick.cycleWindows)
                    }
                }
            }
            Section {
                Text("New docks always start floating in the middle of the main screen.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Button("Reset to Built-in Defaults") { model.store.updateSettings { $0.newDocks = NewDockDefaults() } }
            }
        }
    }
}

private struct IconLibrarySettings: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var address = ""
    @State private var deleting: IconAsset?

    var body: some View {
        let icons = model.store.config.icons.filter { query.isEmpty || $0.fileName.localizedCaseInsensitiveContains(query) }
        Form {
            Section {
                HStack {
                    Button("Import Images…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = true
                        NSApp.activate()
                        if panel.runModal() == .OK { for url in panel.urls { _ = IconLibrary.importFile(url, model: model) } }
                    }
                    TextField("Image address", text: $address, prompt: Text("Paste an image address"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button("Download") { Task { _ = await IconLibrary.download(address, model: model); address = "" } }
                        .disabled(URL(string: address)?.scheme?.hasPrefix("http") != true)
                }
            }
            Section("\(model.store.config.icons.count) icons") {
                if icons.isEmpty {
                    Text("Import images here, or pick one for an item in the Manager.").foregroundStyle(Tokens.textMuted)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: Tokens.Space.m) {
                        ForEach(icons) { asset in
                            let uses = IconLibrary.usage(of: asset.id, in: model.store.docks)
                            VStack {
                                if let image = IconProvider.customIcon(asset.id, library: model.store.config.icons,
                                                                       directory: model.file.iconsDirectory) {
                                    Image(nsImage: image).resizable().frame(width: 48, height: 48)
                                }
                                Text(uses.isEmpty ? "Unused" : "In use (\(uses.count))").font(.caption2)
                                    .foregroundStyle(Tokens.textMuted)
                            }
                            .contextMenu { Button("Delete…", role: .destructive) { deleting = asset } }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .confirmationDialog(Copy.deleteIcon(model.playful), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { asset in
            Button("Remove and Delete", role: .destructive) { IconLibrary.delete(asset.id, model: model) }
        } message: { asset in
            let uses = IconLibrary.usage(of: asset.id, in: model.store.docks)
            Text(uses.isEmpty ? "It isn't used on any dock."
                 : "These items go back to their own icons: " + uses.map { "\($0.item) (\($0.dock))" }.joined(separator: ", "))
        }
    }
}

private struct PreviewSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.store.settings.previews.enabled
        Form {
            Section {
                Toggle("Show window previews when hovering an open app", isOn: model.setting(\.previews.enabled))
                Text("Thumbnails need Screen Recording permission. Without it, previews list window titles.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
            }
            Section("Which windows") {
                Toggle("Only this desktop's windows", isOn: model.setting(\.previews.currentSpaceOnly))
                Toggle("Include minimized windows", isOn: model.setting(\.previews.includeMinimized))
                Toggle("Include hidden apps' windows", isOn: model.setting(\.previews.includeHidden))
                Picker("Order", selection: model.setting(\.previews.sort)) {
                    Text("Most recent first").tag(PreviewSort.recent)
                    Text("Alphabetical").tag(PreviewSort.alphabetical)
                    Text("Oldest first").tag(PreviewSort.creation)
                    Text("Screen position").tag(PreviewSort.screenPosition)
                }
            }
            .disabled(!on)
            Section("Timing and size") {
                ValueSlider(title: "Show after", value: model.setting(\.previews.showDelay), range: 0...1, format: "%.2f", unit: " s")
                ValueSlider(title: "Hide after", value: model.setting(\.previews.hideDelay), range: 0...2, format: "%.2f", unit: " s")
                ValueSlider(title: "Card width", value: model.setting(\.previews.cardWidth), range: 100...600, unit: " pt")
                Stepper("Rows: \(model.store.settings.previews.maxRows)", value: model.setting(\.previews.maxRows), in: 1...8)
                Stepper("Columns: \(model.store.settings.previews.maxColumns)", value: model.setting(\.previews.maxColumns), in: 1...8)
                Toggle("Show the app name", isOn: model.setting(\.previews.showAppName))
                Toggle("Show window titles", isOn: model.setting(\.previews.showWindowTitle))
            }
            .disabled(!on)
        }
    }
}

private struct PermissionsSettings: View {
    @State private var tick = 0

    var body: some View {
        Form {
            Section {
                row("Accessibility",
                    use: "Bringing back a specific window, minimizing, stepping through windows, and keeping windows off docks.",
                    missing: "Clicking an app just switches to it.",
                    granted: WindowControl.isTrusted,
                    request: { WindowControl.requestTrust() },
                    pane: "Privacy_Accessibility")
                row("Screen Recording",
                    use: "Window preview thumbnails.",
                    missing: "Previews show a list of window titles instead.",
                    granted: CGPreflightScreenCaptureAccess(),
                    request: { CGRequestScreenCaptureAccess() },
                    pane: "Privacy_ScreenCapture")
                row("Automation (Finder)",
                    use: "Emptying the Trash from the Trash widget.",
                    missing: "The Trash widget opens the Trash in Finder to empty it there.",
                    granted: nil,
                    request: nil,
                    pane: "Privacy_Automation")
            }
            Section {
                Text("Harbor asks for each permission only when a feature needs it. Checks happen on this Mac and nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Button("Check Again") { tick += 1 }
            }
        }
        .id(tick)
    }

    private func row(_ name: String, use: String, missing: String, granted: Bool?, request: (() -> Void)?, pane: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text(granted == nil ? "Asked when first used" : granted! ? "Allowed" : "Not allowed")
                    .font(.caption)
                    .foregroundStyle(granted == true ? Tokens.success : Tokens.textMuted)
            }
            Text("Used for: \(use)").font(.callout)
            Text("Without it: \(missing)").font(.caption).foregroundStyle(Tokens.textMuted)
            HStack {
                if let request, granted == false { Button("Ask macOS", action: request) }
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
        .padding(.vertical, Tokens.Space.xs)
    }
}

private struct BackupSettings: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var pendingImport: Config?

    var body: some View {
        Form {
            Section("Everything") {
                Text("Docks, settings and custom icons in one file.").font(.caption).foregroundStyle(Tokens.textMuted)
                HStack {
                    Button("Export Backup…") { exportFull() }
                    Button("Import Backup…") { pickImport() }
                }
            }
            Section("Settings only") {
                HStack {
                    Button("Export Settings…") { exportSettings() }
                    Button("Import Settings…") { importSettings() }
                }
            }
            Section("Automatic backups") {
                let snapshots = model.file.snapshots()
                if snapshots.isEmpty {
                    Text("None yet. Harbor keeps about a week of daily copies.").foregroundStyle(Tokens.textMuted)
                }
                ForEach(snapshots.prefix(10)) { s in
                    LabeledContent(s.date.formatted(date: .abbreviated, time: .shortened), value: s.reason.title)
                }
                Button("Restore…") { model.showingRestore = true; model.windows.showManager() }
            }
            if let message { Text(message).font(.callout) }
        }
        .confirmationDialog("Import this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            presenting: pendingImport) { backup in
            Button("Import") {
                _ = try? model.file.snapshotCurrent(reason: .beforeImport)
                let result = model.store.importBackup(backup)
                message = "Added \(result.added) and replaced \(result.replaced) docks."
            }
        } message: { backup in
            let existing = Set(model.store.docks.map(\.id))
            let replaced = backup.docks.filter { existing.contains($0.id) }.count
            Text("Adds \(backup.docks.count - replaced) docks and replaces \(replaced). Your app settings are replaced too. A copy of your current setup is saved first.")
        }
    }

    private func exportFull() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Harbor Backup.harborbackup"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackupArchive.write(config: model.store.config, iconsDirectory: model.file.iconsDirectory, to: url)
            message = "Saved."
            Celebration.shared.play(window: NSApp.keyWindow)
        } catch {
            message = error.localizedDescription
        }
    }

    private func pickImport() {
        let panel = NSOpenPanel()
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImport = try BackupArchive.read(from: url, iconsDirectory: model.file.iconsDirectory)
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Harbor Settings.json"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONEncoder().encode(model.store.settings) else { return }
        try? data.write(to: url, options: .atomic)
        message = "Saved."
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            message = "That file isn't a Harbor settings export."
            return
        }
        model.store.updateSettings { $0 = settings }
        message = "Settings imported. Your docks weren't changed."
    }
}

/// A full backup: the config plus custom icons, as one JSON document.
enum BackupArchive {
    private struct Archive: Codable {
        var config: Config
        var icons: [String: Data]
    }

    static func write(config: Config, iconsDirectory: URL, to url: URL) throws {
        var icons: [String: Data] = [:]
        for asset in config.icons {
            icons[asset.fileName] = try? Data(contentsOf: iconsDirectory.appendingPathComponent(asset.fileName))
        }
        try JSONEncoder().encode(Archive(config: config, icons: icons)).write(to: url, options: .atomic)
    }

    static func read(from url: URL, iconsDirectory: URL) throws -> Config {
        guard let archive = try? JSONDecoder().decode(Archive.self, from: Data(contentsOf: url)) else {
            throw ConfigError.unreadable
        }
        if archive.config.schemaVersion > Config.currentSchemaVersion {
            throw ConfigError.newerVersion(archive.config.schemaVersion)
        }
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        for (name, data) in archive.icons {
            try? data.write(to: iconsDirectory.appendingPathComponent(name))
        }
        return archive.config
    }
}

private struct DiagnosticsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Button("Export Logs…") { Diagnostics.exportLogs() }
                Button("Export Dock Diagnostics…") { Diagnostics.exportDocks(model: model) }
                Button("Export Screen Diagnostics…") { Diagnostics.exportScreens(model: model) }
            }
            Section {
                Text("Exports are saved where you choose and never sent automatically. Item paths and window titles are left out of dock diagnostics.")
                    .font(.caption).foregroundStyle(Tokens.textMuted)
                Link("Report a problem on GitHub", destination: URL(string: "https://github.com/Albertlungu/harbor/issues")!)
            }
        }
    }
}
