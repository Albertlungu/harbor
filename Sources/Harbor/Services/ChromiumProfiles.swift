import AppKit

/// Named profiles of Chromium-based browsers, read from each browser's Local State file.
enum ChromiumProfiles {
    struct Profile: Hashable {
        let name: String
        let directory: String
    }

    private static let supportFolders: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]

    static func isChromium(_ bundleID: String?) -> Bool {
        bundleID.map { supportFolders[$0] != nil } ?? false
    }

    static func profiles(for bundleID: String) -> [Profile] {
        guard let folder = supportFolders[bundleID] else { return [] }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/Local State")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        return cache.compactMap { dir, info in
            // Guest and temporary profiles are not offered.
            if info["is_ephemeral"] as? Bool == true || dir.hasPrefix("Guest") { return nil }
            return Profile(name: info["name"] as? String ?? dir, directory: dir)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func open(_ profile: Profile, appPath: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--profile-directory=\(profile.directory)", "--new-window"]
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: config)
    }
}
