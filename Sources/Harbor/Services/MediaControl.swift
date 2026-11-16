import AppKit

/// Now-playing info and transport control for Music and Spotify.
///
/// MPNowPlayingInfoCenter only exposes what this app itself publishes, so it cannot see other apps.
/// Scripting the players is the supported route; each is touched only while it is running,
/// because addressing a closed app by name would launch it.
@MainActor
final class MediaControl {
    static let shared = MediaControl()

    enum Player: String, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct Track: Equatable {
        let player: Player
        let title: String
        let artist: String
        let playing: Bool
    }

    private var cache: [Track] = []
    private var cachedAt = Date.distantPast

    /// Tracks of running players, refreshed at most every couple of seconds.
    func tracks() -> [Track] {
        guard Date().timeIntervalSince(cachedAt) > 2 else { return cache }
        cache = Player.allCases.compactMap { $0.isRunning ? track(of: $0) : nil }
        cachedAt = Date()
        return cache
    }

    func togglePlayPause(_ player: Player) { send("playpause", to: player) }
    func next(_ player: Player) { send("next track", to: player) }
    func previous(_ player: Player) { send("previous track", to: player) }

    private func send(_ command: String, to player: Player) {
        guard player.isRunning else { return }
        _ = run("tell application \"\(player.rawValue)\" to \(command)")
        cachedAt = .distantPast
    }

    private func track(of player: Player) -> Track? {
        let script = """
        tell application "\(player.rawValue)"
            if player state is stopped then return ""
            return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as text)
        end tell
        """
        guard let output = run(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 3 else { return nil }
        return Track(player: player, title: parts[0], artist: parts[1], playing: parts[2] == "playing")
    }

    /// Runs a script and returns its string result; any failure (including denied Automation access) is nil.
    private func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }
}
