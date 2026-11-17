import AppKit
import HarborCore

/// Reads (and for deep-hide, adjusts) the native macOS Dock's preferences.
@MainActor
final class NativeDock {
    enum Entry: Equatable {
        case app(String)
        case spacer(Int)
    }

    private var cached: (date: Date, entries: [Entry])?

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }

    private func readPlist() -> [String: Any]? {
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    var isReadable: Bool { readPlist() != nil }

    /// Pinned apps and spacers in order; refreshed when the plist changes.
    func entries() -> [Entry] {
        let modified = (try? plistURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached, let modified, cached.date == modified { return cached.entries }
        var result: [Entry] = []
        let apps = readPlist()?["persistent-apps"] as? [[String: Any]] ?? []
        for (i, tile) in apps.enumerated() {
            let type = tile["tile-type"] as? String ?? ""
            if type.contains("spacer") {
                result.append(.spacer(i))
            } else if let path = Self.path(of: tile) {
                result.append(.app(path))
            }
        }
        cached = modified.map { ($0, result) }
        return result
    }

    /// Pinned folders and files from the right side of the native Dock.
    func others() -> [String] {
        let tiles = readPlist()?["persistent-others"] as? [[String: Any]] ?? []
        return tiles.compactMap(Self.path(of:))
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let urlString = file["_CFURLString"] as? String else { return nil }
        if let url = URL(string: urlString), url.isFileURL { return url.path }
        return urlString.hasPrefix("/") ? urlString : nil
    }

    // MARK: Deep hide

    private static let savedKey = "nativeDockSaved"
    private static let hiddenDelay = 9999.0

    /// One detached shell runs the writes, reads them back and only then restarts the Dock,
    /// so the Dock never relaunches before cfprefsd holds the new values.
    private static let hideScript = """
        defaults write com.apple.dock autohide -bool true
        defaults write com.apple.dock autohide-delay -float 9999
        [ "$(defaults read com.apple.dock autohide)" = 1 ] || exit 1
        [ "$(defaults read com.apple.dock autohide-delay)" = 9999 ] || exit 1
        killall Dock
        exit 0
        """

    private var guardObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var guardTimer: Timer?
    private var lastReassert: Date = .distantPast
    /// The delay alone no longer holds the Dock back on macOS 26 and later; see `DockPushGuard`.
    private let pushGuard = DockPushGuard()

    /// Pushes the native Dock out of the way with a 9999-second auto-hide delay, saving prior values,
    /// then keeps watching so the delay is put back if anything else resets it.
    func deepHide() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: Self.savedKey) == nil {
            let current = readPlist() ?? [:]
            var saved: [String: Any] = [:]
            saved["autohide"] = current["autohide"] as? Bool ?? false
            if let delay = current["autohide-delay"] { saved["autohide-delay"] = delay }
            defaults.set(saved, forKey: Self.savedKey)
        }
        let ok = shell(Self.hideScript)
        lastReassert = Date()
        startGuard()
        return ok
    }

    /// True when the macOS Dock is still hidden by an earlier session, e.g. after a crash.
    var isHiddenByHarbor: Bool { UserDefaults.standard.dictionary(forKey: Self.savedKey) != nil }

    /// Whether the Dock's live preferences, as cfprefsd serves them rather than the possibly
    /// stale file on disk, still hold the deep-hide values.
    var isDeepHidden: Bool {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, domain) as? Bool ?? false
        let delay = (CFPreferencesCopyAppValue("autohide-delay" as CFString, domain) as? NSNumber)?.doubleValue ?? 0
        return autohide && delay >= Self.hiddenDelay
    }

    /// Restores what `deepHide` saved.
    func restore() -> Bool {
        stopGuard()
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey) else { return true }
        let autohide = (saved["autohide"] as? Bool ?? false) ? "true" : "false"
        let delay = (saved["autohide-delay"] as? NSNumber).map { "defaults write com.apple.dock autohide-delay -float \($0.doubleValue)" }
            ?? "defaults delete com.apple.dock autohide-delay 2>/dev/null"
        let ok = shell("""
            defaults write com.apple.dock autohide -bool \(autohide)
            \(delay)
            killall Dock
            exit 0
            """)
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
        return ok
    }

    /// System Settings, other utilities or a macOS update can rewrite the Dock's preferences while
    /// Harbor runs; the delay was found reset to 5 seconds, which let the Dock slide up under the
    /// bottom docks. Checks are cheap reads; the Dock only restarts on real drift.
    private func startGuard() {
        pushGuard.start()
        guard guardTimer == nil else { return }
        guardTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertIfNeeded() }
        }
        let check: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertIfNeeded() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            guardObservers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main, using: check)))
        }
        let nc = NotificationCenter.default
        guardObservers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                  object: nil, queue: .main, using: check)))
    }

    private func stopGuard() {
        pushGuard.stop()
        guardTimer?.invalidate()
        guardTimer = nil
        for observer in guardObservers { observer.center.removeObserver(observer.token) }
        guardObservers.removeAll()
    }

    private func reassertIfNeeded() {
        // Also picks up display changes, and starts the tap once Accessibility is granted.
        pushGuard.start()
        // Restarting the Dock in a loop would be worse than it showing, so drift is corrected
        // at most twice a minute.
        guard !isDeepHidden, Date().timeIntervalSince(lastReassert) > 30 else { return }
        lastReassert = Date()
        _ = shell(Self.hideScript)
    }

    private func shell(_ script: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
